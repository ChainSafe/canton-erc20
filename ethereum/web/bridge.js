/**
 * Wayfinder Bridge Test Interface
 * JavaScript logic for interacting with CantonBridge on Sepolia
 */

// =============================================================================
// ABI Definitions
// =============================================================================

const BRIDGE_ABI = [
    // Core deposit/withdrawal functions
    "function depositToCanton(address token, uint256 amount, bytes32 cantonRecipient) returns (uint256 nonce)",
    "function executeLargeWithdrawal(bytes32 withdrawalId)",
    "function cancelLargeWithdrawal(bytes32 withdrawalId)",

    // View functions
    "function getLockedBalance(address token) view returns (uint256)",
    "function isTokenRegistered(address token) view returns (bool)",
    "function processedWithdrawals(bytes32) view returns (bool)",
    "function queuedWithdrawals(bytes32) view returns (address token, uint256 amount, address recipient, uint256 executeAfter)",
    "function timeLockDelay() view returns (uint256)",
    "function depositNonces(address) view returns (uint256)",
    "function registeredTokens(address) view returns (bool)",
    "function lockedBalances(address) view returns (uint256)",
    "function largeWithdrawalThresholds(address) view returns (uint256)",

    // Rate limit functions (from RateLimiter)
    "function getRateLimit(address token) view returns (uint256 maxAmount, uint256 period, uint256 lastReset, uint256 usedAmount)",
    "function getRemainingRateLimit(address token) view returns (uint256)",

    // Events
    "event DepositToCanton(address indexed token, address indexed sender, uint256 amount, bytes32 indexed cantonRecipient, uint256 nonce)",
    "event WithdrawalFromCanton(address indexed token, address indexed recipient, uint256 amount, bytes32 indexed cantonSender, bytes32 withdrawalId)",
    "event WithdrawalProcessed(bytes32 indexed withdrawalId, bool success)",
    "event LargeWithdrawalQueued(bytes32 indexed withdrawalId, address indexed token, uint256 amount, uint256 executeAfter)",
    "event LargeWithdrawalCancelled(bytes32 indexed withdrawalId)",
    "event TokenRegistered(address indexed token, string symbol, bytes32 indexed cantonTokenId, bool isNative)",
    "event TokenDeregistered(address indexed token)",
    "event BridgePaused(address indexed by)",
    "event BridgeUnpaused(address indexed by)",
    "event RateLimitSet(address indexed token, uint256 amount, uint256 period)",
    "event EmergencyWithdrawal(address indexed token, uint256 amount, address indexed recipient)"
];

const ERC20_ABI = [
    "function approve(address spender, uint256 amount) returns (bool)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function balanceOf(address account) view returns (uint256)",
    "function symbol() view returns (string)",
    "function name() view returns (string)",
    "function decimals() view returns (uint8)",
    "function totalSupply() view returns (uint256)",
    "function mint(address to, uint256 amount)"
];

// =============================================================================
// Configuration
// =============================================================================

const CONFIG = {
    rpcUrl: 'https://eth-sepolia.g.alchemy.com/v2/MeMdx3uk0ZFuSy2YFs0VAGjG7gXf0wJP',
    bridgeAddress: '0x523a865Bf51d93df22Fb643e6BDE2F66438e32c2',
    chainId: 11155111,
    explorerUrl: 'https://sepolia.etherscan.io'
};

// =============================================================================
// Activity Logger Class
// =============================================================================

class ActivityLogger {
    constructor(containerId) {
        this.container = document.getElementById(containerId);
        this.maxLogs = 500;
        this.icons = {
            api: '\u2192',      // →
            event: '\u25CF',    // ●
            error: '\u2717',    // ✗
            success: '\u2713',  // ✓
            info: 'i',
            tx: '\u2B21',       // ⬡
            warn: '\u26A0'      // ⚠
        };
    }

    log(type, message, details = null) {
        if (!this.container) return;

        const entry = document.createElement('div');
        entry.className = `log-entry log-${type}`;

        const time = new Date().toLocaleTimeString();
        const icon = this.icons[type] || 'i';

        let html = `
            <span class="log-time">${time}</span>
            <span class="log-icon">${icon}</span>
            <span class="log-msg">${this.escapeHtml(message)}</span>
        `;

        if (details) {
            html += `<div class="log-details">${this.formatDetails(details)}</div>`;
        }

        entry.innerHTML = html;
        this.container.insertBefore(entry, this.container.firstChild);
        this.trimLogs();

        // Also log to console for debugging
        console.log(`[${type.toUpperCase()}] ${message}`, details || '');
    }

    api(method, endpoint, params = null) {
        const shortEndpoint = endpoint.replace(/https?:\/\/[^/]+/, '');
        this.log('api', `${method} ${shortEndpoint}`, params);
    }

    event(name, data = null) {
        this.log('event', name, data);
    }

    error(message, err = null) {
        this.log('error', message, err?.message || err);
    }

    success(message, data = null) {
        this.log('success', message, data);
    }

    info(message, data = null) {
        this.log('info', message, data);
    }

    tx(message, hash = null) {
        this.log('tx', message, hash ? `TX: ${hash}` : null);
    }

    warn(message, data = null) {
        this.log('warn', message, data);
    }

    formatDetails(details) {
        if (typeof details === 'string') {
            return this.escapeHtml(details);
        }
        if (typeof details === 'object') {
            try {
                const str = JSON.stringify(details, null, 2);
                // Truncate long values
                return this.escapeHtml(str.length > 500 ? str.slice(0, 500) + '...' : str);
            } catch {
                return String(details);
            }
        }
        return String(details);
    }

    escapeHtml(str) {
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    trimLogs() {
        while (this.container.children.length > this.maxLogs) {
            this.container.removeChild(this.container.lastChild);
        }
    }

    clear() {
        if (this.container) {
            this.container.innerHTML = `
                <div class="log-entry log-info">
                    <span class="log-time">${new Date().toLocaleTimeString()}</span>
                    <span class="log-icon">i</span>
                    <span class="log-msg">Log cleared</span>
                </div>
            `;
        }
    }
}

// =============================================================================
// Bridge Interface Class
// =============================================================================

class BridgeInterface {
    constructor() {
        this.provider = null;
        this.signer = null;
        this.bridge = null;
        this.readProvider = null;
        this.readBridge = null;
        this.isListening = false;
        this.eventCount = 0;
        this.userFingerprint = null;  // Cached fingerprint after registration
        this.logger = new ActivityLogger('activity-log');
        this.ethereum = null;  // Store MetaMask provider reference for event handling
        this.isConnected = false;
    }

    /**
     * Compute fingerprint from EVM address (keccak256 hash).
     * This matches the server-side computation in auth/evm.go
     */
    computeFingerprint(address) {
        // keccak256 of the address bytes (ethers handles the conversion)
        return ethers.keccak256(address);
    }

    /**
     * Truncate a long hex string for display.
     * Shows first N and last M characters with ellipsis in between.
     */
    truncateHash(hash, prefixLen = 10, suffixLen = 8) {
        if (!hash) return '-';
        if (hash.length <= prefixLen + suffixLen + 3) return hash;
        return `${hash.slice(0, prefixLen)}...${hash.slice(-suffixLen)}`;
    }

    /**
     * Create HTML for a truncated hash with copy button.
     * Returns HTML string with copy functionality.
     */
    formatHashWithCopy(hash, label = '') {
        if (!hash) return `${label}<code>-</code>`;
        const truncated = this.truncateHash(hash, 14, 10);
        const id = `hash-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
        return `
            ${label}<span class="hash-display">
                <code title="${hash}">${truncated}</code>
                <button class="copy-btn" onclick="navigator.clipboard.writeText('${hash}').then(() => { this.textContent='Copied!'; this.classList.add('copied'); setTimeout(() => { this.textContent='Copy'; this.classList.remove('copied'); }, 1500); })">Copy</button>
            </span>
        `;
    }

    async init() {
        // Initialize read-only provider for event listening
        this.readProvider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
        this.readBridge = new ethers.Contract(CONFIG.bridgeAddress, BRIDGE_ABI, this.readProvider);

        // Update UI
        document.getElementById('bridge-addr-display').textContent =
            CONFIG.bridgeAddress.slice(0, 6) + '...' + CONFIG.bridgeAddress.slice(-4);

        this.logger.info('Bridge interface initialized');
        this.logger.info(`Bridge: ${CONFIG.bridgeAddress.slice(0, 10)}...`);
        this.logger.info(`Chain ID: ${CONFIG.chainId} (Sepolia)`);

        // Expose to window for clear button
        window.bridgeInterface = this;
    }

    /**
     * Set up event listeners for account and chain changes.
     * Called once after successful connection.
     */
    setupEventListeners() {
        if (!this.ethereum) return;

        // Remove any existing listeners to prevent duplicates
        if (this._handleAccountsChanged) {
            this.ethereum.removeListener('accountsChanged', this._handleAccountsChanged);
        }
        if (this._handleChainChanged) {
            this.ethereum.removeListener('chainChanged', this._handleChainChanged);
        }

        // Bind handlers to preserve 'this' context
        this._handleAccountsChanged = (accounts) => {
            if (accounts.length === 0) {
                this.handleDisconnect();
            } else {
                this.handleAccountChange(accounts[0]);
            }
        };

        this._handleChainChanged = (chainId) => {
            this.handleChainChange(chainId);
        };

        // Add listeners
        this.ethereum.on('accountsChanged', this._handleAccountsChanged);
        this.ethereum.on('chainChanged', this._handleChainChanged);

        this.logger.info('Event listeners set up for account/chain changes');
    }

    /**
     * Handle account change from MetaMask.
     * Updates signer, UI, and clears cached fingerprint.
     */
    async handleAccountChange(newAddress) {
        this.logger.info(`Account changed in MetaMask: ${newAddress.slice(0, 10)}...`);

        try {
            // Update signer with new account
            this.signer = await this.provider.getSigner();
            const address = await this.signer.getAddress();

            // Recreate bridge contract with new signer
            this.bridge = new ethers.Contract(CONFIG.bridgeAddress, BRIDGE_ABI, this.signer);

            // Update UI
            document.getElementById('wallet-status').textContent =
                address.slice(0, 6) + '...' + address.slice(-4);

            // Clear cached fingerprint - user needs to re-register with new account
            this.userFingerprint = null;
            document.getElementById('canton-recipient').value = '';
            document.getElementById('canton-recipient').style.background = '';
            document.getElementById('fingerprint-help').innerHTML =
                '<span style="color: #e67e22;">Account changed. Please register again.</span>';
            document.getElementById('deposit-btn').disabled = true;

            // Clear Canton account status
            document.getElementById('canton-account-status').innerHTML =
                '<div class="tx-pending">Account changed. Please register to link this wallet.</div>';

            this.logger.success(`Now using account: ${address.slice(0, 10)}...`);
        } catch (e) {
            this.logger.error('Failed to update account', e);
        }
    }

    /**
     * Handle chain/network change from MetaMask.
     * Warns user if they switch away from Sepolia.
     */
    handleChainChange(chainIdHex) {
        const chainId = parseInt(chainIdHex, 16);
        this.logger.info(`Chain changed to: ${chainId}`);

        if (chainId !== CONFIG.chainId) {
            document.getElementById('network-name').textContent = `Chain ${chainId} (WRONG!)`;
            document.getElementById('network-name').style.color = '#e74c3c';
            this.logger.warn(`Wrong network! Expected Sepolia (${CONFIG.chainId}), got ${chainId}`);
        } else {
            document.getElementById('network-name').textContent = 'Sepolia';
            document.getElementById('network-name').style.color = '#27ae60';
            this.logger.success('Connected to Sepolia');
        }
    }

    /**
     * Handle wallet disconnection.
     * Resets UI and state.
     */
    handleDisconnect() {
        this.logger.info('Wallet disconnected');

        this.signer = null;
        this.bridge = null;
        this.userFingerprint = null;
        this.isConnected = false;

        // Update UI
        document.getElementById('wallet-dot').classList.remove('connected');
        document.getElementById('wallet-dot').classList.add('disconnected');
        document.getElementById('wallet-status').textContent = 'Not connected';
        document.getElementById('connect-wallet').textContent = 'Connect Wallet';
        document.getElementById('connect-wallet').disabled = false;

        // Clear fingerprint
        document.getElementById('canton-recipient').value = '';
        document.getElementById('canton-recipient').style.background = '';
        document.getElementById('deposit-btn').disabled = true;

        // Clear Canton account status
        document.getElementById('canton-account-status').innerHTML = '';
    }

    /**
     * Disconnect wallet by revoking permissions.
     * This is the recommended way to allow users to select a different account.
     * See: https://docs.metamask.io/wallet/how-to/access-accounts/
     */
    async disconnectWallet() {
        if (!this.ethereum) {
            this.handleDisconnect();
            return;
        }

        this.logger.info('Revoking wallet permissions...');

        try {
            // Revoke the eth_accounts permission - this is the official way to "disconnect"
            await this.ethereum.request({
                method: 'wallet_revokePermissions',
                params: [{ eth_accounts: {} }]
            });
            this.logger.success('Wallet permissions revoked. You can now connect with a different account.');
        } catch (e) {
            // Some wallets may not support wallet_revokePermissions
            this.logger.warn('wallet_revokePermissions not supported', e.message);
        }

        this.handleDisconnect();
    }

    /**
     * Find MetaMask provider specifically, even when multiple wallets are installed.
     * Handles EIP-5749 multi-provider standard used when Phantom/MetaMask coexist.
     */
    findMetaMaskProvider() {
        if (!window.ethereum) {
            console.log('[Bridge] No ethereum provider found');
            return null;
        }

        // EIP-5749: Check if providers array exists (multiple wallets installed)
        if (window.ethereum.providers && Array.isArray(window.ethereum.providers)) {
            console.log('[Bridge] Multiple providers detected:', window.ethereum.providers.length);

            // Find MetaMask specifically
            for (const provider of window.ethereum.providers) {
                if (provider.isMetaMask && !provider.isPhantom) {
                    console.log('[Bridge] Found MetaMask in providers array');
                    return provider;
                }
            }

            // Log what we found for debugging
            window.ethereum.providers.forEach((p, i) => {
                console.log(`[Bridge] Provider ${i}: isMetaMask=${p.isMetaMask}, isPhantom=${p.isPhantom}`);
            });

            console.log('[Bridge] MetaMask not found in providers array');
            return null;
        }

        // Single provider - check if it's MetaMask (not Phantom pretending to be MetaMask)
        if (window.ethereum.isMetaMask && !window.ethereum.isPhantom) {
            console.log('[Bridge] Single MetaMask provider found');
            return window.ethereum;
        }

        // Phantom sets isMetaMask=true but also isPhantom=true
        if (window.ethereum.isPhantom) {
            console.log('[Bridge] Only Phantom found, MetaMask not available');
            return null;
        }

        console.log('[Bridge] Unknown provider, attempting to use');
        return window.ethereum;
    }

    async connectWallet() {
        // Find MetaMask specifically when multiple wallets are installed
        let ethereum = this.findMetaMaskProvider();

        if (!ethereum) {
            throw new Error('MetaMask not found. Please install MetaMask or disable other wallet extensions.');
        }

        // Store reference for event listeners
        this.ethereum = ethereum;

        console.log('[Bridge] Using provider:', ethereum.isMetaMask ? 'MetaMask' : 'Unknown');

        // For MetaMask: Switch to Sepolia FIRST before connecting
        const sepoliaChainId = '0xaa36a7'; // 11155111 in hex

        try {
            console.log('[Bridge] Requesting switch to Sepolia...');
            await ethereum.request({
                method: 'wallet_switchEthereumChain',
                params: [{ chainId: sepoliaChainId }]
            });
            console.log('[Bridge] Switched to Sepolia');
        } catch (switchError) {
            console.log('[Bridge] Switch error code:', switchError.code);
            if (switchError.code === 4902) {
                // Chain not in MetaMask, add it
                console.log('[Bridge] Sepolia not found, adding...');
                await ethereum.request({
                    method: 'wallet_addEthereumChain',
                    params: [{
                        chainId: sepoliaChainId,
                        chainName: 'Sepolia',
                        nativeCurrency: { name: 'Sepolia ETH', symbol: 'ETH', decimals: 18 },
                        rpcUrls: ['https://rpc.sepolia.org'],
                        blockExplorerUrls: ['https://sepolia.etherscan.io']
                    }]
                });
            } else if (switchError.code === 4001) {
                throw new Error('You rejected the network switch. Please switch to Sepolia manually in MetaMask.');
            } else {
                console.error('[Bridge] Switch error:', switchError);
            }
        }

        // Request fresh permissions - this forces MetaMask to show account selection popup
        // This is key to letting user choose which account to connect
        console.log('[Bridge] Requesting account permissions...');
        this.logger.info('MetaMask popup opened. Click "Edit accounts" to select a different account.');
        try {
            await ethereum.request({
                method: 'wallet_requestPermissions',
                params: [{ eth_accounts: {} }]
            });
            console.log('[Bridge] Permissions granted, getting accounts...');
        } catch (permError) {
            if (permError.code === 4001) {
                throw new Error('You rejected the account selection. Please try again and select an account.');
            }
            if (permError.code === -32002) {
                // Request already pending - tell user to check MetaMask
                throw new Error('MetaMask has a pending request. Please click the MetaMask extension icon to complete or cancel it, then try again.');
            }
            // Some wallets may not support wallet_requestPermissions, fall back to eth_requestAccounts
            console.log('[Bridge] wallet_requestPermissions not supported, using eth_requestAccounts');
        }

        // Now get the accounts the user selected
        this.provider = new ethers.BrowserProvider(ethereum);
        await this.provider.send("eth_requestAccounts", []);
        this.signer = await this.provider.getSigner();

        const address = await this.signer.getAddress();
        console.log('[Bridge] Connected address:', address);

        // Verify we're on Sepolia
        const network = await this.provider.getNetwork();
        const chainId = Number(network.chainId);
        console.log('[Bridge] Connected on chain ID:', chainId);

        if (chainId !== CONFIG.chainId) {
            console.warn('[Bridge] WARNING: On wrong network!');
            document.getElementById('network-name').textContent = `Chain ${chainId} (WRONG!)`;
            document.getElementById('network-name').style.color = '#e74c3c';
            alert(`Still on chain ${chainId}. Please manually switch to Sepolia in MetaMask.`);
        } else {
            console.log('[Bridge] Successfully connected to Sepolia!');
            document.getElementById('network-name').textContent = 'Sepolia';
            document.getElementById('network-name').style.color = '#27ae60';
        }

        this.bridge = new ethers.Contract(CONFIG.bridgeAddress, BRIDGE_ABI, this.signer);
        this.isConnected = true;

        const connectedAddress = await this.signer.getAddress();
        console.log('[Bridge] Wallet connected:', connectedAddress);

        // Set up event listeners for account/chain changes
        this.setupEventListeners();

        // Update UI - button becomes "Disconnect" and stays enabled
        document.getElementById('wallet-dot').classList.remove('disconnected');
        document.getElementById('wallet-dot').classList.add('connected');
        document.getElementById('wallet-status').textContent =
            connectedAddress.slice(0, 6) + '...' + connectedAddress.slice(-4);
        document.getElementById('connect-wallet').textContent = 'Disconnect';
        document.getElementById('connect-wallet').disabled = false;  // Keep enabled for disconnecting

        this.logger.success(`Wallet connected: ${connectedAddress.slice(0, 10)}...`);
        return connectedAddress;
    }

    // =========================================================================
    // Deposit Functions
    // =========================================================================

    async getTokenInfo(tokenAddress) {
        const token = new ethers.Contract(tokenAddress, ERC20_ABI, this.readProvider);
        const [symbol, name, decimals] = await Promise.all([
            token.symbol(),
            token.name(),
            token.decimals()
        ]);
        return { symbol, name, decimals: Number(decimals) };
    }

    /**
     * Get ERC20 token balance and allowance for the connected user.
     * Returns { balance, allowance, symbol, decimals }
     */
    async getTokenBalanceAndAllowance(tokenAddress) {
        if (!this.signer) throw new Error('Wallet not connected');

        const userAddress = await this.signer.getAddress();
        const token = new ethers.Contract(tokenAddress, ERC20_ABI, this.readProvider);
        const tokenInfo = await this.getTokenInfo(tokenAddress);

        const [balance, allowance] = await Promise.all([
            token.balanceOf(userAddress),
            token.allowance(userAddress, CONFIG.bridgeAddress)
        ]);

        return {
            balance: ethers.formatUnits(balance, tokenInfo.decimals),
            allowance: ethers.formatUnits(allowance, tokenInfo.decimals),
            symbol: tokenInfo.symbol,
            decimals: tokenInfo.decimals,
            balanceRaw: balance,
            allowanceRaw: allowance
        };
    }

    /**
     * Update the UI to show the user's fingerprint and enable deposit.
     */
    setUserFingerprint(fingerprint) {
        this.userFingerprint = fingerprint;
        document.getElementById('canton-recipient').value = fingerprint;
        document.getElementById('canton-recipient').style.background = '#d4edda';
        document.getElementById('fingerprint-help').innerHTML =
            '<span style="color: #27ae60;">✓ Fingerprint set. Ready to deposit!</span>';
        document.getElementById('deposit-btn').disabled = false;
        this.logger.success(`Fingerprint set: ${fingerprint.slice(0, 20)}...`);
    }

    async approve(tokenAddress, amount) {
        if (!this.signer) throw new Error('Wallet not connected');

        const token = new ethers.Contract(tokenAddress, ERC20_ABI, this.signer);
        const tokenInfo = await this.getTokenInfo(tokenAddress);
        const amountWei = ethers.parseUnits(amount.toString(), tokenInfo.decimals);

        this.logger.api('CALL', `ERC20.approve(${CONFIG.bridgeAddress.slice(0,10)}...)`, { amount, token: tokenAddress.slice(0,10) });
        this.showTxPending('Approving token spend...');
        const tx = await token.approve(CONFIG.bridgeAddress, amountWei);
        this.logger.tx(`Approval TX submitted`, tx.hash);
        this.showTxPending(`Approval TX submitted: ${tx.hash}`);

        const receipt = await tx.wait();
        this.logger.success(`Approved ${amount} ${tokenInfo.symbol}`);
        this.showTxSuccess(`Approved ${amount} ${tokenInfo.symbol}`, tx.hash);
        return receipt;
    }

    async deposit(tokenAddress, amount, cantonRecipient) {
        if (!this.signer) throw new Error('Wallet not connected');

        // Validate canton recipient
        if (!cantonRecipient.startsWith('0x') || cantonRecipient.length !== 66) {
            throw new Error('Canton recipient must be 32 bytes (0x + 64 hex chars)');
        }

        // Check if token is registered
        const isRegistered = await this.bridge.isTokenRegistered(tokenAddress);
        if (!isRegistered) {
            throw new Error('Token not registered with bridge');
        }

        const tokenInfo = await this.getTokenInfo(tokenAddress);
        const amountWei = ethers.parseUnits(amount.toString(), tokenInfo.decimals);

        // Check allowance
        const token = new ethers.Contract(tokenAddress, ERC20_ABI, this.signer);
        const userAddress = await this.signer.getAddress();
        const allowance = await token.allowance(userAddress, CONFIG.bridgeAddress);

        if (allowance < amountWei) {
            throw new Error(`Insufficient allowance. Please approve first. Current: ${ethers.formatUnits(allowance, tokenInfo.decimals)}`);
        }

        this.logger.api('CALL', `Bridge.depositToCanton()`, { amount, recipient: cantonRecipient.slice(0,20) });
        this.showTxPending('Submitting deposit transaction...');
        const tx = await this.bridge.depositToCanton(tokenAddress, amountWei, cantonRecipient);
        this.logger.tx('Deposit TX submitted', tx.hash);
        this.showTxPending(`Deposit TX submitted: ${tx.hash}`);

        const receipt = await tx.wait();
        this.logger.success(`Deposited ${amount} ${tokenInfo.symbol} to Canton`);
        this.showTxSuccess(`Deposited ${amount} ${tokenInfo.symbol} to Canton`, tx.hash);
        return receipt;
    }

    // =========================================================================
    // Canton Account Functions (Registration & Balance)
    // =========================================================================

    /**
     * Register the connected wallet with the Canton bridge.
     * Creates a FingerprintMapping on Canton linking the EVM address to a Canton party.
     */
    async registerWallet(apiUrl) {
        if (!this.signer) throw new Error('Wallet not connected');

        const userAddress = await this.signer.getAddress();
        const timestamp = Math.floor(Date.now() / 1000);
        const message = `user_register:${timestamp}`;

        // Sign the message for authentication
        const signature = await this.signer.signMessage(message);

        const rpcRequest = {
            jsonrpc: '2.0',
            method: 'user_register',
            params: {},
            id: 1
        };

        this.logger.api('POST', apiUrl, { method: 'user_register', address: userAddress.slice(0,10) });

        const response = await fetch(apiUrl, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Signature': signature,
                'X-Message': message
            },
            body: JSON.stringify(rpcRequest)
        });

        const result = await response.json();

        if (result.error) {
            this.logger.error('Registration failed', result.error);
            throw new Error(result.error.message || result.error.data || 'Registration failed');
        }

        this.logger.success('Registration successful', { fingerprint: result.result?.fingerprint?.slice(0,20) });
        return result.result;
    }

    /**
     * Check the Canton balance for the connected wallet.
     */
    async checkCantonBalance(apiUrl) {
        if (!this.signer) throw new Error('Wallet not connected');

        const userAddress = await this.signer.getAddress();
        const timestamp = Math.floor(Date.now() / 1000);
        const message = `erc20_balanceOf:${timestamp}`;

        // Sign the message for authentication
        const signature = await this.signer.signMessage(message);

        const rpcRequest = {
            jsonrpc: '2.0',
            method: 'erc20_balanceOf',
            params: {},
            id: 1
        };

        this.logger.api('POST', apiUrl, { method: 'erc20_balanceOf', address: userAddress.slice(0,10) });

        const response = await fetch(apiUrl, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Signature': signature,
                'X-Message': message
            },
            body: JSON.stringify(rpcRequest)
        });

        const result = await response.json();

        if (result.error) {
            this.logger.error('Balance check failed', result.error);
            throw new Error(result.error.message || result.error.data || 'Balance check failed');
        }

        this.logger.success(`Canton balance: ${result.result.balance}`);
        return result.result;
    }

    // =========================================================================
    // Withdrawal Functions (Canton → EVM)
    // =========================================================================

    /**
     * Initiate a withdrawal from Canton via the middleware RPC API.
     * This calls erc20_withdraw which creates a withdrawal event on Canton.
     * The middleware then processes it and releases tokens on EVM.
     */
    async initiateWithdrawal(apiUrl, amount, destination) {
        if (!this.signer) throw new Error('Wallet not connected');

        const userAddress = await this.signer.getAddress();
        const timestamp = Math.floor(Date.now() / 1000);
        const message = `erc20_withdraw:${timestamp}`;

        // Sign the message for authentication
        const signature = await this.signer.signMessage(message);

        // Prepare RPC request
        const params = { amount };
        if (destination && destination.trim()) {
            params.to = destination.trim();
        }

        const rpcRequest = {
            jsonrpc: '2.0',
            method: 'erc20_withdraw',
            params: params,
            id: 1
        };

        this.logger.api('POST', apiUrl, { method: 'erc20_withdraw', amount, destination: destination || userAddress });

        const response = await fetch(apiUrl, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Signature': signature,
                'X-Message': message
            },
            body: JSON.stringify(rpcRequest)
        });

        const result = await response.json();

        if (result.error) {
            this.logger.error('Withdrawal failed', result.error);
            throw new Error(result.error.message || result.error.data || 'Withdrawal failed');
        }

        this.logger.success(`Withdrawal initiated`, { id: result.result?.withdrawalId?.slice(0,20), amount });
        return result.result;
    }

    async executeWithdrawal(withdrawalId) {
        if (!this.signer) throw new Error('Wallet not connected');

        // Validate withdrawal ID
        if (!withdrawalId.startsWith('0x') || withdrawalId.length !== 66) {
            throw new Error('Withdrawal ID must be 32 bytes (0x + 64 hex chars)');
        }

        // Check if already processed
        const processed = await this.bridge.processedWithdrawals(withdrawalId);
        if (processed) {
            throw new Error('Withdrawal already processed');
        }

        // Check if queued
        const queued = await this.bridge.queuedWithdrawals(withdrawalId);
        if (queued.executeAfter === 0n) {
            throw new Error('Withdrawal not found in queue');
        }

        // Check time lock
        const now = BigInt(Math.floor(Date.now() / 1000));
        if (now < queued.executeAfter) {
            const remaining = Number(queued.executeAfter - now);
            throw new Error(`Withdrawal still time-locked. ${remaining} seconds remaining.`);
        }

        this.logger.api('CALL', 'Bridge.executeLargeWithdrawal()', { withdrawalId: withdrawalId.slice(0,20) });
        this.showTxPending('Executing withdrawal...');
        const tx = await this.bridge.executeLargeWithdrawal(withdrawalId);
        this.logger.tx('Execute TX submitted', tx.hash);
        this.showTxPending(`Execute TX submitted: ${tx.hash}`);

        const receipt = await tx.wait();
        this.logger.success('Withdrawal executed successfully');
        this.showTxSuccess('Withdrawal executed successfully', tx.hash);
        return receipt;
    }

    async cancelWithdrawal(withdrawalId) {
        if (!this.signer) throw new Error('Wallet not connected');

        if (!withdrawalId.startsWith('0x') || withdrawalId.length !== 66) {
            throw new Error('Withdrawal ID must be 32 bytes (0x + 64 hex chars)');
        }

        this.logger.api('CALL', 'Bridge.cancelLargeWithdrawal()', { withdrawalId: withdrawalId.slice(0,20) });
        this.showTxPending('Cancelling withdrawal...');
        const tx = await this.bridge.cancelLargeWithdrawal(withdrawalId);
        this.logger.tx('Cancel TX submitted', tx.hash);
        this.showTxPending(`Cancel TX submitted: ${tx.hash}`);

        const receipt = await tx.wait();
        this.logger.success('Withdrawal cancelled');
        this.showTxSuccess('Withdrawal cancelled', tx.hash);
        return receipt;
    }

    // =========================================================================
    // Query Functions
    // =========================================================================

    async queryBridgeState(tokenAddress) {
        if (!tokenAddress) {
            document.getElementById('state-registered').textContent = '-';
            document.getElementById('state-locked').textContent = '-';
            document.getElementById('state-rate-max').textContent = '-';
            document.getElementById('state-rate-used').textContent = '-';
            document.getElementById('state-rate-remaining').textContent = '-';
            return;
        }

        try {
            const tokenInfo = await this.getTokenInfo(tokenAddress);
            const [isRegistered, lockedBalance, timeLockDelay] = await Promise.all([
                this.readBridge.isTokenRegistered(tokenAddress),
                this.readBridge.lockedBalances(tokenAddress),
                this.readBridge.timeLockDelay()
            ]);

            document.getElementById('state-registered').textContent = isRegistered ? 'Yes' : 'No';
            document.getElementById('state-locked').textContent =
                ethers.formatUnits(lockedBalance, tokenInfo.decimals) + ' ' + tokenInfo.symbol;
            document.getElementById('state-timelock').textContent =
                Number(timeLockDelay) / 3600 + ' hours';

            // Try to get rate limit (may not be set)
            try {
                const rateLimit = await this.readBridge.getRateLimit(tokenAddress);
                const remaining = await this.readBridge.getRemainingRateLimit(tokenAddress);

                document.getElementById('state-rate-max').textContent =
                    ethers.formatUnits(rateLimit.maxAmount, tokenInfo.decimals) + ' ' + tokenInfo.symbol;
                document.getElementById('state-rate-used').textContent =
                    ethers.formatUnits(rateLimit.usedAmount, tokenInfo.decimals) + ' ' + tokenInfo.symbol;
                document.getElementById('state-rate-remaining').textContent =
                    ethers.formatUnits(remaining, tokenInfo.decimals) + ' ' + tokenInfo.symbol;
            } catch (e) {
                document.getElementById('state-rate-max').textContent = 'Not set';
                document.getElementById('state-rate-used').textContent = '-';
                document.getElementById('state-rate-remaining').textContent = '-';
            }

        } catch (e) {
            console.error('Query failed:', e);
            document.getElementById('state-registered').textContent = 'Error: ' + e.message;
        }
    }

    async queryQueuedWithdrawal(withdrawalId) {
        const queued = await this.readBridge.queuedWithdrawals(withdrawalId);
        if (queued.executeAfter === 0n) return null;

        const tokenInfo = await this.getTokenInfo(queued.token);
        const now = BigInt(Math.floor(Date.now() / 1000));

        return {
            token: queued.token,
            tokenSymbol: tokenInfo.symbol,
            amount: ethers.formatUnits(queued.amount, tokenInfo.decimals),
            recipient: queued.recipient,
            executeAfter: new Date(Number(queued.executeAfter) * 1000).toLocaleString(),
            canExecute: now >= queued.executeAfter,
            secondsRemaining: now < queued.executeAfter ? Number(queued.executeAfter - now) : 0
        };
    }

    // =========================================================================
    // Event Listening
    // =========================================================================

    startEventListening() {
        if (this.isListening) return;
        this.isListening = true;

        this.logger.info('Started event listening on bridge contract');

        // Listen to all events
        this.readBridge.on('DepositToCanton', (token, sender, amount, cantonRecipient, nonce, event) => {
            this.logger.event('DepositToCanton', { sender: sender.slice(0,10), amount: ethers.formatUnits(amount, 18) });
            this.addEventToLog('DepositToCanton', 'deposit', {
                token,
                sender,
                amount: ethers.formatUnits(amount, 18),
                cantonRecipient,
                nonce: nonce.toString()
            }, event);
        });

        this.readBridge.on('WithdrawalFromCanton', (token, recipient, amount, cantonSender, withdrawalId, event) => {
            this.logger.event('WithdrawalFromCanton', { recipient: recipient.slice(0,10), amount: ethers.formatUnits(amount, 18) });
            this.addEventToLog('WithdrawalFromCanton', 'withdrawal', {
                token,
                recipient,
                amount: ethers.formatUnits(amount, 18),
                cantonSender,
                withdrawalId
            }, event);
        });

        this.readBridge.on('WithdrawalProcessed', (withdrawalId, success, event) => {
            this.logger.event('WithdrawalProcessed', { success, id: withdrawalId.slice(0,20) });
            this.addEventToLog('WithdrawalProcessed', 'processed', {
                withdrawalId,
                success
            }, event);
        });

        this.readBridge.on('LargeWithdrawalQueued', (withdrawalId, token, amount, executeAfter, event) => {
            this.logger.event('LargeWithdrawalQueued', { amount: ethers.formatUnits(amount, 18) });
            this.addEventToLog('LargeWithdrawalQueued', 'queued', {
                withdrawalId,
                token,
                amount: ethers.formatUnits(amount, 18),
                executeAfter: new Date(Number(executeAfter) * 1000).toLocaleString()
            }, event);
        });

        this.readBridge.on('LargeWithdrawalCancelled', (withdrawalId, event) => {
            this.logger.event('LargeWithdrawalCancelled', { id: withdrawalId.slice(0,20) });
            this.addEventToLog('LargeWithdrawalCancelled', 'cancelled', {
                withdrawalId
            }, event);
        });

        this.readBridge.on('TokenRegistered', (token, symbol, cantonTokenId, isNative, event) => {
            this.logger.event('TokenRegistered', { symbol, token: token.slice(0,10) });
            this.addEventToLog('TokenRegistered', 'deposit', {
                token,
                symbol,
                cantonTokenId,
                isNative
            }, event);
        });
    }

    stopEventListening() {
        if (!this.isListening) return;
        this.readBridge.removeAllListeners();
        this.isListening = false;
        this.logger.info('Stopped event listening');
    }

    async loadEventHistory(blocks = 100) {
        this.logger.info(`Loading events from last ${blocks} blocks...`);

        const currentBlock = await this.readProvider.getBlockNumber();
        const fromBlock = currentBlock - blocks;

        const events = await Promise.all([
            this.readBridge.queryFilter('DepositToCanton', fromBlock, currentBlock),
            this.readBridge.queryFilter('WithdrawalFromCanton', fromBlock, currentBlock),
            this.readBridge.queryFilter('WithdrawalProcessed', fromBlock, currentBlock),
            this.readBridge.queryFilter('LargeWithdrawalQueued', fromBlock, currentBlock),
            this.readBridge.queryFilter('LargeWithdrawalCancelled', fromBlock, currentBlock)
        ]);

        // Flatten and sort by block number
        const allEvents = events.flat().sort((a, b) => a.blockNumber - b.blockNumber);

        this.logger.success(`Found ${allEvents.length} events in history`);

        for (const event of allEvents) {
            const eventName = event.fragment.name;
            let eventClass = 'deposit';
            let data = {};

            switch (eventName) {
                case 'DepositToCanton':
                    eventClass = 'deposit';
                    data = {
                        token: event.args[0],
                        sender: event.args[1],
                        amount: ethers.formatUnits(event.args[2], 18),
                        cantonRecipient: event.args[3],
                        nonce: event.args[4].toString()
                    };
                    break;
                case 'WithdrawalFromCanton':
                    eventClass = 'withdrawal';
                    data = {
                        token: event.args[0],
                        recipient: event.args[1],
                        amount: ethers.formatUnits(event.args[2], 18),
                        cantonSender: event.args[3],
                        withdrawalId: event.args[4]
                    };
                    break;
                case 'WithdrawalProcessed':
                    eventClass = 'processed';
                    data = {
                        withdrawalId: event.args[0],
                        success: event.args[1]
                    };
                    break;
                case 'LargeWithdrawalQueued':
                    eventClass = 'queued';
                    data = {
                        withdrawalId: event.args[0],
                        token: event.args[1],
                        amount: ethers.formatUnits(event.args[2], 18),
                        executeAfter: new Date(Number(event.args[3]) * 1000).toLocaleString()
                    };
                    break;
                case 'LargeWithdrawalCancelled':
                    eventClass = 'cancelled';
                    data = { withdrawalId: event.args[0] };
                    break;
            }

            this.addEventToLog(eventName, eventClass, data, event, false);
        }
    }

    // =========================================================================
    // UI Helpers
    // =========================================================================

    addEventToLog(eventName, eventClass, data, event, prepend = true) {
        const eventLog = document.getElementById('event-log');

        // Remove empty state if present
        const emptyState = eventLog.querySelector('.empty-state');
        if (emptyState) emptyState.remove();

        this.eventCount++;
        const timestamp = new Date().toLocaleTimeString();

        const html = `
            <div class="event-item ${eventClass}">
                <div class="event-header">
                    <span class="event-name">${eventName}</span>
                    <span class="event-time">${timestamp}</span>
                </div>
                <div class="event-data">${this.formatEventData(data)}</div>
                <div class="event-tx">
                    Block: ${event.blockNumber} |
                    <a href="${CONFIG.explorerUrl}/tx/${event.transactionHash}" target="_blank">
                        View on Etherscan
                    </a>
                </div>
            </div>
        `;

        if (prepend) {
            eventLog.insertAdjacentHTML('afterbegin', html);
        } else {
            eventLog.insertAdjacentHTML('beforeend', html);
        }
    }

    formatEventData(data) {
        return Object.entries(data).map(([key, value]) => {
            let displayValue = value;
            if (typeof value === 'string' && value.startsWith('0x') && value.length > 20) {
                displayValue = value.slice(0, 10) + '...' + value.slice(-8);
            }
            return `<strong>${key}:</strong> ${displayValue}`;
        }).join('<br>');
    }

    showTxPending(message) {
        document.getElementById('tx-status').innerHTML = `
            <div class="tx-pending">
                <strong>Pending:</strong> ${message}
            </div>
        `;
    }

    showTxSuccess(message, txHash) {
        document.getElementById('tx-status').innerHTML = `
            <div class="tx-success">
                <strong>Success:</strong> ${message}<br>
                <a href="${CONFIG.explorerUrl}/tx/${txHash}" target="_blank">View on Etherscan</a>
            </div>
        `;
    }

    showTxError(message) {
        document.getElementById('tx-status').innerHTML = `
            <div class="tx-error">
                <strong>Error:</strong> ${message}
            </div>
        `;
    }

    log(message) {
        // Legacy method - redirect to logger
        this.logger.info(message);
    }

    // =========================================================================
    // Stuck Transfers Functions (Relayer API)
    // =========================================================================

    /**
     * Fetch stuck transfers from the relayer API
     */
    async fetchStuckTransfers(relayerUrl) {
        const url = `${relayerUrl}/transfers/stuck`;
        this.logger.api('GET', url);

        try {
            const response = await fetch(url);
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }
            const data = await response.json();
            this.logger.success(`Found ${data.transfers?.length || 0} stuck transfers`);
            return data.transfers || [];
        } catch (e) {
            this.logger.error('Failed to fetch stuck transfers', e);
            throw e;
        }
    }

    /**
     * Retry a failed transfer
     */
    async retryTransfer(relayerUrl, transferId) {
        const url = `${relayerUrl}/transfers/${encodeURIComponent(transferId)}/retry`;
        this.logger.api('POST', url, { id: transferId });

        try {
            const response = await fetch(url, { method: 'POST' });
            if (!response.ok) {
                const text = await response.text();
                throw new Error(text || `HTTP ${response.status}`);
            }
            const data = await response.json();
            this.logger.success(`Transfer ${transferId} marked for retry`);
            return data;
        } catch (e) {
            this.logger.error(`Failed to retry transfer ${transferId}`, e);
            throw e;
        }
    }

    /**
     * Render stuck transfers in the UI
     */
    renderStuckTransfers(transfers, container, relayerUrl) {
        if (!transfers || transfers.length === 0) {
            container.innerHTML = '<div class="empty-state" style="padding: 20px;">No stuck transfers found</div>';
            return;
        }

        const html = transfers.map(t => {
            const statusClass = t.Status === 'failed' ? 'failed' : 'pending';
            const direction = t.Direction === 'canton_to_ethereum' ? 'Canton to EVM' : 'EVM to Canton';

            // Format amount (assuming 18 decimals)
            let amountDisplay = t.Amount;
            try {
                const amountBigInt = BigInt(t.Amount);
                const formatted = ethers.formatUnits(amountBigInt, 18);
                amountDisplay = parseFloat(formatted).toFixed(4);
            } catch (e) {
                // If not a valid bigint, just display as-is
            }

            return `
                <div class="stuck-transfer ${statusClass}">
                    <div class="stuck-transfer-header">
                        <span class="stuck-transfer-id">${t.ID}</span>
                        <span class="stuck-transfer-status ${statusClass}">${t.Status.toUpperCase()}</span>
                    </div>
                    <div class="stuck-transfer-details">
                        <span><strong>Direction:</strong> ${direction}</span>
                        <span><strong>Amount:</strong> ${amountDisplay}</span>
                        <span><strong>Retries:</strong> ${t.RetryCount || 0}</span>
                    </div>
                    <div class="stuck-transfer-details">
                        <span><strong>Recipient:</strong> ${t.Recipient ? t.Recipient.slice(0, 20) + '...' : '-'}</span>
                        ${t.ErrorMessage ? `<span style="color: #e74c3c;"><strong>Error:</strong> ${t.ErrorMessage}</span>` : ''}
                    </div>
                    <div class="stuck-transfer-actions">
                        <button class="btn-warning retry-transfer-btn" data-id="${t.ID}">Retry</button>
                    </div>
                </div>
            `;
        }).join('');

        container.innerHTML = html;

        // Add event listeners for retry buttons
        container.querySelectorAll('.retry-transfer-btn').forEach(btn => {
            btn.addEventListener('click', async (e) => {
                const id = e.target.dataset.id;
                e.target.disabled = true;
                e.target.textContent = 'Retrying...';
                try {
                    await this.retryTransfer(relayerUrl, id);
                    alert(`Transfer ${id} marked for retry!`);
                    // Refresh the list
                    await this.refreshStuckTransfers(relayerUrl);
                } catch (err) {
                    alert('Retry failed: ' + err.message);
                    e.target.disabled = false;
                    e.target.textContent = 'Retry';
                }
            });
        });
    }

    /**
     * Refresh and render stuck transfers
     */
    async refreshStuckTransfers(relayerUrl) {
        const container = document.getElementById('stuck-transfers');
        container.innerHTML = '<div class="empty-state" style="padding: 20px;">Loading...</div>';

        try {
            const transfers = await this.fetchStuckTransfers(relayerUrl);
            this.renderStuckTransfers(transfers, container, relayerUrl);
        } catch (e) {
            container.innerHTML = `<div class="tx-error" style="margin: 10px;">Error: ${e.message}</div>`;
        }
    }
}

// =============================================================================
// Initialize Application
// =============================================================================

let app;

document.addEventListener('DOMContentLoaded', async () => {
    app = new BridgeInterface();
    await app.init();

    // Connect wallet button - handles both connect and disconnect
    document.getElementById('connect-wallet').addEventListener('click', async () => {
        try {
            if (app.isConnected) {
                // If connected, disconnect first (revoke permissions)
                await app.disconnectWallet();
            } else {
                // If not connected, connect
                await app.connectWallet();
            }
        } catch (e) {
            alert('Failed: ' + e.message);
        }
    });

    // Apply configuration
    document.getElementById('apply-config').addEventListener('click', () => {
        CONFIG.rpcUrl = document.getElementById('rpc-url').value;
        CONFIG.bridgeAddress = document.getElementById('bridge-address').value;
        CONFIG.chainId = parseInt(document.getElementById('chain-id').value);

        app.stopEventListening();
        app.init();
        alert('Configuration applied');
    });

    // Approve button
    document.getElementById('approve-btn').addEventListener('click', async () => {
        const token = document.getElementById('token-address').value;
        const amount = document.getElementById('deposit-amount').value;

        if (!token) {
            alert('Please enter a token address');
            return;
        }

        try {
            await app.approve(token, amount);
        } catch (e) {
            app.showTxError(e.message);
            console.error(e);
        }
    });

    // Deposit button
    document.getElementById('deposit-btn').addEventListener('click', async () => {
        const token = document.getElementById('token-address').value;
        const amount = document.getElementById('deposit-amount').value;
        const recipient = document.getElementById('canton-recipient').value;

        if (!token) {
            alert('Please enter a token address');
            return;
        }

        // Validate fingerprint
        if (!recipient || !recipient.startsWith('0x') || recipient.length !== 66) {
            alert('Invalid fingerprint! Please register your wallet first to get your Canton fingerprint.');
            return;
        }

        // Warn if fingerprint doesn't match computed fingerprint
        if (app.signer && app.userFingerprint && recipient !== app.userFingerprint) {
            const proceed = confirm(
                'WARNING: The Canton Recipient fingerprint does not match your registered fingerprint!\n\n' +
                'Your fingerprint: ' + app.userFingerprint.slice(0, 20) + '...\n' +
                'Entered fingerprint: ' + recipient.slice(0, 20) + '...\n\n' +
                'If you deposit to a different fingerprint, you may lose your tokens!\n\n' +
                'Are you sure you want to continue?'
            );
            if (!proceed) return;
        }

        try {
            await app.deposit(token, amount, recipient);
        } catch (e) {
            app.showTxError(e.message);
            console.error(e);
        }
    });

    // Register wallet button
    document.getElementById('register-btn').addEventListener('click', async () => {
        const apiUrl = document.getElementById('api-url').value;
        const statusDiv = document.getElementById('canton-account-status');

        try {
            statusDiv.innerHTML = '<div class="tx-pending">Signing message and registering wallet...</div>';
            const result = await app.registerWallet(apiUrl);

            // Auto-populate fingerprint in deposit form
            if (result.fingerprint) {
                app.setUserFingerprint(result.fingerprint);
            }

            statusDiv.innerHTML = `
                <div class="tx-success">
                    <strong>Registration Successful!</strong><br>
                    <strong>Party:</strong> <code style="font-size: 10px;">${result.party?.slice(0, 40)}...</code><br>
                    <strong>Fingerprint:</strong> <code style="font-size: 10px;">${result.fingerprint}</code><br>
                    <em style="color: #27ae60;">✓ Fingerprint auto-populated in deposit form!</em>
                </div>
            `;
        } catch (e) {
            // If already registered, compute fingerprint locally and set it
            if (e.message.includes('already registered')) {
                try {
                    const address = await app.signer.getAddress();
                    const fingerprint = app.computeFingerprint(address);
                    app.setUserFingerprint(fingerprint);
                    statusDiv.innerHTML = `
                        <div class="tx-success">
                            <strong>Already Registered!</strong><br>
                            <strong>Fingerprint:</strong> <code style="font-size: 10px;">${fingerprint}</code><br>
                            <em style="color: #27ae60;">✓ Fingerprint auto-populated in deposit form!</em>
                        </div>
                    `;
                    return;
                } catch (innerErr) {
                    console.error('Failed to compute fingerprint:', innerErr);
                }
            }
            statusDiv.innerHTML = `<div class="tx-error"><strong>Error:</strong> ${e.message}</div>`;
            console.error(e);
        }
    });

    // Refresh ERC20 balance button
    document.getElementById('refresh-balance-btn').addEventListener('click', async () => {
        const tokenAddress = document.getElementById('token-address').value;
        const balanceDisplay = document.getElementById('token-balance-display');
        const balanceSpan = document.getElementById('erc20-balance');
        const allowanceSpan = document.getElementById('erc20-allowance');

        if (!app.signer) {
            alert('Please connect your wallet first');
            return;
        }

        try {
            balanceDisplay.style.display = 'block';
            balanceSpan.textContent = 'Loading...';
            allowanceSpan.textContent = 'Loading...';

            const info = await app.getTokenBalanceAndAllowance(tokenAddress);
            balanceSpan.textContent = `${info.balance} ${info.symbol}`;
            allowanceSpan.textContent = `${info.allowance} ${info.symbol}`;

            // Color code the allowance
            if (parseFloat(info.allowance) > 0) {
                allowanceSpan.style.color = '#27ae60';
            } else {
                allowanceSpan.style.color = '#e74c3c';
            }
        } catch (e) {
            balanceSpan.textContent = 'Error: ' + e.message;
            console.error(e);
        }
    });

    // Check Canton balance button
    document.getElementById('check-balance-btn').addEventListener('click', async () => {
        const apiUrl = document.getElementById('api-url').value;
        const statusDiv = document.getElementById('canton-account-status');

        try {
            statusDiv.innerHTML = '<div class="tx-pending">Checking Canton balance...</div>';
            const result = await app.checkCantonBalance(apiUrl);
            const balance = parseFloat(result.balance);  // Balance is already in token units
            statusDiv.innerHTML = `
                <div class="tx-success">
                    <strong>Canton Balance:</strong> ${balance.toFixed(6)} PROMPT<br>
                    <strong>Address:</strong> ${result.address}
                </div>
            `;
        } catch (e) {
            statusDiv.innerHTML = `<div class="tx-error"><strong>Error:</strong> ${e.message}</div>`;
            console.error(e);
        }
    });

    // Initiate withdrawal button (Canton → EVM via middleware)
    document.getElementById('initiate-withdraw-btn').addEventListener('click', async () => {
        const apiUrl = document.getElementById('api-url').value;
        const amount = document.getElementById('withdraw-amount').value;
        const destination = document.getElementById('withdraw-destination').value;

        if (!amount) {
            alert('Please enter a withdrawal amount');
            return;
        }

        const statusDiv = document.getElementById('withdraw-status');

        try {
            statusDiv.innerHTML = '<div class="tx-pending">Signing message and initiating withdrawal...</div>';
            const result = await app.initiateWithdrawal(apiUrl, amount, destination);
            const withdrawalIdHtml = app.formatHashWithCopy(result.withdrawalId, '<strong>Withdrawal ID:</strong> ');
            statusDiv.innerHTML = `
                <div class="tx-success">
                    <strong>Withdrawal Initiated!</strong><br>
                    <strong>Amount:</strong> ${result.amount}<br>
                    <strong>Destination:</strong> ${result.evmDestination}<br>
                    ${withdrawalIdHtml}<br>
                    <em style="display: block; margin-top: 8px;">${result.message}</em>
                </div>
            `;
        } catch (e) {
            statusDiv.innerHTML = `<div class="tx-error"><strong>Error:</strong> ${e.message}</div>`;
            console.error(e);
        }
    });

    // Execute withdrawal button (for large/timelocked withdrawals)
    document.getElementById('execute-withdrawal-btn').addEventListener('click', async () => {
        const withdrawalId = document.getElementById('withdrawal-id').value;

        if (!withdrawalId) {
            alert('Please enter a withdrawal ID');
            return;
        }

        try {
            await app.executeWithdrawal(withdrawalId);
        } catch (e) {
            app.showTxError(e.message);
            console.error(e);
        }
    });

    // Cancel withdrawal button
    document.getElementById('cancel-withdrawal-btn').addEventListener('click', async () => {
        const withdrawalId = document.getElementById('withdrawal-id').value;

        if (!withdrawalId) {
            alert('Please enter a withdrawal ID');
            return;
        }

        try {
            await app.cancelWithdrawal(withdrawalId);
        } catch (e) {
            app.showTxError(e.message);
            console.error(e);
        }
    });

    // Query state button
    document.getElementById('query-state-btn').addEventListener('click', async () => {
        const token = document.getElementById('query-token').value;
        await app.queryBridgeState(token);
    });

    // Event listening buttons (optional - may not exist in all UI versions)
    const startListeningBtn = document.getElementById('start-listening');
    if (startListeningBtn) {
        startListeningBtn.addEventListener('click', () => {
            app.startEventListening();
            startListeningBtn.textContent = 'Listening...';
            startListeningBtn.disabled = true;
        });
    }

    const loadHistoryBtn = document.getElementById('load-history');
    if (loadHistoryBtn) {
        loadHistoryBtn.addEventListener('click', async () => {
            await app.loadEventHistory(100);
        });
    }

    const clearEventsBtn = document.getElementById('clear-events');
    if (clearEventsBtn) {
        clearEventsBtn.addEventListener('click', () => {
            document.getElementById('event-log').innerHTML =
                '<div class="empty-state">Click "Start Listening" to begin receiving events</div>';
            app.eventCount = 0;
        });
    }

    // Stuck transfers refresh button
    document.getElementById('refresh-stuck-btn').addEventListener('click', async () => {
        const relayerUrl = document.getElementById('relayer-url').value;
        await app.refreshStuckTransfers(relayerUrl);
    });
});
