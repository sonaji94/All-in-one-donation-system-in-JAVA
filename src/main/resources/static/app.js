/**
 * ==============================================================================
 * IMPACTFUND - FULL-STACK PRODUCTION CLIENT ENGINE (app.js)
 * Architecture: Vanilla ES6+, Fetch API, Razorpay Checkout SDK, Stateless JWT
 * ==============================================================================
 */

// ------------------------------------------------------------------------------
// 1. CONFIGURATION & STATE MANAGEMENT
// ------------------------------------------------------------------------------
const DEFAULT_API_BASE = window.location.origin.includes('8080')
    ? window.location.origin
    : (localStorage.getItem('impactfund_api_base') || 'http://localhost:8080');

const AppState = {
    apiBase: DEFAULT_API_BASE.replace(/\/+$/, ''),
    isMockMode: localStorage.getItem('impactfund_mock_mode') === 'true',
    user: JSON.parse(localStorage.getItem('impactfund_user') || 'null'),
    campaigns: [],
    selectedCampaign: null,
    selectedAmount: 500,
    lastReceipt: null
};

// Realistic mock fallback campaigns for immediate offline preview
const MOCK_CAMPAIGNS = [
    {
        id: "b1eebc99-9c0b-4ef8-bb6d-6bb9bd380b22",
        title: "Emergency Flood Relief & Clean Water Initiative",
        description: "Deploying emergency sustenance kits, clean potable drinking water filtration units, and mobile trauma care to displaced families in river basin villages.",
        targetAmount: 500000.00,
        collectedAmount: 384500.00,
        percentageFunded: 76.90,
        status: "ACTIVE",
        ownerName: "Platform Administrator",
        category: "Disaster Relief"
    },
    {
        id: "c2eebc99-9c0b-4ef8-bb6d-6bb9bd380c33",
        title: "Solar Electrification for Rural Community Hospitals",
        description: "Installing uninterrupted 10kW hybrid solar power banks for critical newborn incubators, blood storage, and surgical theatres in remote health clinics.",
        targetAmount: 350000.00,
        collectedAmount: 215000.00,
        percentageFunded: 61.43,
        status: "ACTIVE",
        ownerName: "Dr. Ananya Sharma",
        category: "Healthcare"
    },
    {
        id: "d3eebc99-9c0b-4ef8-bb6d-6bb9bd380d44",
        title: "STEM Laboratories & Digital Literacy for Rural Youth",
        description: "Equipping 12 public schools with refurbished computer labs, high-speed satellite internet terminals, and robotics starter kits for 1,800 students.",
        targetAmount: 200000.00,
        collectedAmount: 189000.00,
        percentageFunded: 94.50,
        status: "ACTIVE",
        ownerName: "Prerna Foundation",
        category: "Education"
    }
];

// ------------------------------------------------------------------------------
// 2. LIFECYCLE INITIALIZATION
// ------------------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', () => {
    initAuthUI();
    loadApiSettingsUI();
    fetchCampaigns();
});

// ------------------------------------------------------------------------------
// 3. API & DATA FETCHING
// ------------------------------------------------------------------------------
async function fetchCampaigns() {
    const banner = document.getElementById('connectionStatusText');
    const container = document.getElementById('campaignsGrid');
    
    // Render loading skeletons
    renderSkeletons();

    if (AppState.isMockMode) {
        banner.innerText = "Offline Preview Mode: Using Mock Datasets";
        banner.parentElement.className = "bg-amber-600 text-white text-xs py-1 px-4 text-center font-medium flex items-center justify-center gap-2";
        AppState.campaigns = [...MOCK_CAMPAIGNS];
        renderCampaigns(AppState.campaigns);
        updateImpactStats(AppState.campaigns);
        return;
    }

    try {
        const response = await fetch(`${AppState.apiBase}/api/v1/campaigns`, {
            headers: { 'Accept': 'application/json' }
        });

        if (!response.ok) throw new Error(`HTTP error ${response.status}`);
        const result = await response.json();

        if (result.success && Array.isArray(result.data) && result.data.length > 0) {
            AppState.campaigns = result.data;
            banner.innerText = `Connected to Spring Boot Live API (${AppState.apiBase})`;
            banner.parentElement.className = "bg-emerald-600 text-white text-xs py-1 px-4 text-center font-medium flex items-center justify-center gap-2";
        } else {
            console.warn("Backend returned empty campaigns list. Populating with initial demo seed.");
            AppState.campaigns = [...MOCK_CAMPAIGNS];
            banner.innerText = `Connected (${AppState.apiBase}) - Default Seed Data`;
        }
    } catch (err) {
        console.warn("Unable to contact Spring Boot API. Activating Offline Mock Fallback.", err.message);
        AppState.campaigns = [...MOCK_CAMPAIGNS];
        banner.innerText = `Backend Offline (${AppState.apiBase}) - Running in Mock Mode`;
        banner.parentElement.className = "bg-slate-700 text-white text-xs py-1 px-4 text-center font-medium flex items-center justify-center gap-2";
    }

    renderCampaigns(AppState.campaigns);
    updateImpactStats(AppState.campaigns);
}

// ------------------------------------------------------------------------------
// 4. UI RENDERING & IMPACT METRICS
// ------------------------------------------------------------------------------
function renderCampaigns(campaigns) {
    const container = document.getElementById('campaignsGrid');
    const emptyState = document.getElementById('emptyCampaignsState');

    if (!campaigns || campaigns.length === 0) {
        container.innerHTML = '';
        emptyState.classList.remove('hidden');
        return;
    }

    emptyState.classList.add('hidden');
    container.innerHTML = campaigns.map(camp => {
        const percentage = Math.min(camp.percentageFunded || 0, 100);
        const formattedCollected = Number(camp.collectedAmount || 0).toLocaleString('en-IN');
        const formattedTarget = Number(camp.targetAmount || 0).toLocaleString('en-IN');
        const category = camp.category || "General Relief";

        return `
            <div class="bg-white rounded-3xl overflow-hidden border border-slate-200/80 shadow-sm campaign-card flex flex-col justify-between" id="card-${camp.id}">
                <div>
                    <!-- Header Banner -->
                    <div class="h-44 bg-gradient-to-br from-slate-800 to-slate-900 p-6 flex flex-col justify-between relative overflow-hidden">
                        <div class="absolute -right-8 -bottom-8 text-white/5 text-9xl font-black pointer-events-none">
                            <i class="fa-solid fa-hand-holding-heart"></i>
                        </div>
                        <div class="flex items-center justify-between z-10">
                            <span class="text-[10px] font-bold uppercase tracking-wider bg-white/20 text-white backdrop-blur-md px-3 py-1 rounded-full">
                                ${category}
                            </span>
                            <span class="text-xs font-bold text-emerald-400 bg-emerald-950/60 border border-emerald-500/30 px-2.5 py-0.5 rounded-full">
                                ${camp.status}
                            </span>
                        </div>
                        <div class="z-10">
                            <span class="text-[11px] text-slate-300 font-medium">Organized by ${escapeHtml(camp.ownerName || 'Verified Organizer')}</span>
                            <h3 class="text-lg font-black text-white mt-1 line-clamp-1 leading-snug">${escapeHtml(camp.title)}</h3>
                        </div>
                    </div>

                    <!-- Body Content -->
                    <div class="p-6">
                        <p class="text-xs text-slate-500 line-clamp-3 leading-relaxed mb-6 font-normal">
                            ${escapeHtml(camp.description)}
                        </p>

                        <!-- Funding Progress Bar -->
                        <div class="space-y-2">
                            <div class="flex items-baseline justify-between text-xs">
                                <span class="font-bold text-slate-900 text-sm">₹${formattedCollected}</span>
                                <span class="text-slate-400 font-medium">Goal: ₹${formattedTarget}</span>
                            </div>
                            <div class="w-full bg-slate-100 rounded-full h-2.5 overflow-hidden">
                                <div class="progress-bar-fill h-2.5 rounded-full" style="width: ${percentage}%"></div>
                            </div>
                            <div class="flex justify-between items-center text-[11px] pt-1">
                                <span class="font-bold text-emerald-600">${percentage}% Funded</span>
                                <span class="text-slate-400"><i class="fa-solid fa-shield-check text-emerald-500"></i> Razorpay Secured</span>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Action Button -->
                <div class="px-6 pb-6 pt-2">
                    <button onclick="openDonationModal('${camp.id}')" class="w-full bg-emerald-600 hover:bg-emerald-700 active:scale-[0.99] text-white font-bold py-3 px-4 rounded-xl shadow-md shadow-emerald-600/15 transition flex items-center justify-center gap-2 text-sm">
                        <i class="fa-solid fa-heart text-xs"></i>
                        <span>Donate to this Cause</span>
                    </button>
                </div>
            </div>
        `;
    }).join('');
}

function updateImpactStats(campaigns) {
    const totalCollected = campaigns.reduce((acc, curr) => acc + Number(curr.collectedAmount || 0), 0);
    const activeCount = campaigns.filter(c => c.status === 'ACTIVE').length;

    document.getElementById('statTotalRaised').innerText = `₹${totalCollected.toLocaleString('en-IN')}`;
    document.getElementById('statActiveCampaigns').innerText = activeCount.toString();
}

function renderSkeletons() {
    const container = document.getElementById('campaignsGrid');
    container.innerHTML = [1, 2, 3].map(() => `
        <div class="bg-white rounded-3xl p-6 border border-slate-200/80 shadow-sm animate-pulse space-y-4">
            <div class="h-32 bg-slate-200 rounded-2xl"></div>
            <div class="h-4 bg-slate-200 rounded w-3/4"></div>
            <div class="h-3 bg-slate-200 rounded w-full"></div>
            <div class="h-3 bg-slate-200 rounded w-2/3"></div>
            <div class="h-2.5 bg-slate-200 rounded-full w-full mt-6"></div>
            <div class="h-10 bg-slate-200 rounded-xl mt-4"></div>
        </div>
    `).join('');
}

// ------------------------------------------------------------------------------
// 5. RAZORPAY CHECKOUT LIFECYCLE
// ------------------------------------------------------------------------------
function openDonationModal(campaignId) {
    const campaign = AppState.campaigns.find(c => c.id === campaignId);
    if (!campaign) {
        showToast("Campaign details not found.", "error");
        return;
    }

    AppState.selectedCampaign = campaign;
    document.getElementById('checkoutCampaignId').value = campaign.id;
    document.getElementById('checkoutCampaignTitle').innerText = campaign.title;
    document.getElementById('checkoutCampaignDesc').innerText = campaign.description;

    // Prefill user details if authenticated
    if (AppState.user) {
        document.getElementById('donorNameInput').value = AppState.user.name || '';
        document.getElementById('donorEmailInput').value = AppState.user.email || '';
    }

    setDonationAmount(500);
    document.getElementById('donationModal').classList.remove('hidden');
}

function closeDonationModal() {
    document.getElementById('donationModal').classList.add('hidden');
}

function setDonationAmount(amount) {
    AppState.selectedAmount = amount;
    document.getElementById('donationAmountInput').value = amount;

    document.querySelectorAll('.preset-chip').forEach(chip => {
        if (chip.innerText.replace(/[₹,]/g, '') == amount) {
            chip.classList.add('active');
        } else {
            chip.classList.remove('active');
        }
    });
}

document.getElementById('donationAmountInput')?.addEventListener('input', (e) => {
    AppState.selectedAmount = parseFloat(e.target.value) || 0;
    document.querySelectorAll('.preset-chip').forEach(chip => chip.classList.remove('active'));
});

async function handleProceedDonation(e) {
    e.preventDefault();
    const btn = document.getElementById('btnPayRazorpay');
    const campaignId = document.getElementById('checkoutCampaignId').value;
    const amount = parseFloat(document.getElementById('donationAmountInput').value);
    const donorName = document.getElementById('donorNameInput').value.trim();
    const donorEmail = document.getElementById('donorEmailInput').value.trim();
    const donorPan = document.getElementById('donorPanInput') ? document.getElementById('donorPanInput').value.trim().toUpperCase() : null;
    const isAnonymous = document.getElementById('donateAnonymousCheckbox').checked;

    if (!amount || amount <= 0) {
        showToast("Please enter a valid donation amount.", "error");
        return;
    }

    btn.disabled = true;
    btn.innerHTML = `<i class="fa-solid fa-circle-notch fa-spin"></i> Preparing Payment...`;

    // Offline / Mock fallback simulation
    if (AppState.isMockMode) {
        setTimeout(() => {
            simulateMockPaymentSuccess(campaignId, amount, donorName, donorEmail);
            btn.disabled = false;
            btn.innerHTML = `<i class="fa-solid fa-lock text-xs"></i> <span>Pay with Razorpay</span>`;
        }, 800);
        return;
    }

    try {
        // STEP 1: Create Order on Spring Boot Backend
        const orderPayload = {
            campaignId,
            amount,
            donorName,
            donorEmail,
            donorPan: donorPan || null,
            isAnonymous
        };

        const headers = { 'Content-Type': 'application/json' };
        if (AppState.user?.token) {
            headers['Authorization'] = `Bearer ${AppState.user.token}`;
        }

        const orderResp = await fetch(`${AppState.apiBase}/api/v1/donations/order`, {
            method: 'POST',
            headers,
            body: JSON.stringify(orderPayload)
        });

        const orderJson = await orderResp.json();

        if (!orderResp.ok || !orderJson.success) {
            throw new Error(orderJson.message || "Failed to initiate payment order on backend.");
        }

        const orderData = orderJson.data;

        // STEP 2: Launch Razorpay Standard Checkout Popup
        const options = {
            key: orderData.keyId,
            amount: Math.round(orderData.amount * 100), // In paise
            currency: orderData.currency || "INR",
            name: "ImpactFund",
            description: `Donation: ${AppState.selectedCampaign.title.substring(0, 30)}...`,
            order_id: orderData.razorpayOrderId,
            handler: async function (callbackPayload) {
                // STEP 3: Cryptographic Signature Handoff & Capture
                showToast("Payment captured. Cryptographically verifying signature on server...", "info");
                try {
                    const verifyPayload = {
                        razorpayOrderId: callbackPayload.razorpay_order_id,
                        razorpayPaymentId: callbackPayload.razorpay_payment_id,
                        razorpaySignature: callbackPayload.razorpay_signature
                    };

                    const verifyResp = await fetch(`${AppState.apiBase}/api/v1/donations/verify`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(verifyPayload)
                    });

                    const verifyJson = await verifyResp.json();

                    if (!verifyResp.ok || !verifyJson.success) {
                        throw new Error(verifyJson.message || "HMAC signature verification rejected by server.");
                    }

                    // Success! Update local campaign model & open receipt modal
                    applyDonationSuccess(campaignId, amount, verifyJson.data);
                } catch (verifyErr) {
                    showToast(`Verification Failed: ${verifyErr.message}`, "error");
                }
            },
            prefill: {
                name: isAnonymous ? "" : donorName,
                email: isAnonymous ? "" : donorEmail
            },
            theme: {
                color: "#059669"
            },
            modal: {
                ondismiss: function () {
                    btn.disabled = false;
                    btn.innerHTML = `<i class="fa-solid fa-lock text-xs"></i> <span>Pay with Razorpay</span>`;
                }
            }
        };

        const rzp = new window.Razorpay(options);
        rzp.open();

    } catch (err) {
        console.error("Payment initiation failed:", err);
        showToast(err.message, "error");
        btn.disabled = false;
        btn.innerHTML = `<i class="fa-solid fa-lock text-xs"></i> <span>Pay with Razorpay</span>`;
    }
}

function simulateMockPaymentSuccess(campaignId, amount, donorName, donorEmail) {
    const mockOrder = "order_mock_" + Date.now();
    const mockPayment = "pay_mock_" + Math.random().toString(36).substring(2, 10);
    const mockData = {
        id: "don_" + Date.now(),
        amount: amount,
        campaignId: campaignId,
        donorName: donorName || "Generous Supporter",
        razorpayOrderId: mockOrder,
        razorpayPaymentId: mockPayment,
        createdAt: new Date().toISOString()
    };

    applyDonationSuccess(campaignId, amount, mockData);
}

function applyDonationSuccess(campaignId, amount, transactionData) {
    closeDonationModal();

    // Increment local campaign funds atomically
    const campaign = AppState.campaigns.find(c => c.id === campaignId);
    if (campaign) {
        campaign.collectedAmount = Number(campaign.collectedAmount || 0) + Number(amount);
        campaign.percentageFunded = Math.round((campaign.collectedAmount / campaign.targetAmount) * 100);
        renderCampaigns(AppState.campaigns);
        updateImpactStats(AppState.campaigns);
    }

    // Populate and open receipt modal
    AppState.lastReceipt = {
        amount: amount,
        campaignTitle: campaign ? campaign.title : "Community Cause",
        paymentId: transactionData.razorpayPaymentId,
        orderId: transactionData.razorpayOrderId,
        donorName: transactionData.donorName || "Anonymous",
        timestamp: new Date().toLocaleString('en-IN')
    };

    document.getElementById('receiptAmount').innerText = `₹${Number(amount).toLocaleString('en-IN')}`;
    document.getElementById('receiptCampaign').innerText = AppState.lastReceipt.campaignTitle;
    document.getElementById('receiptPaymentId').innerText = AppState.lastReceipt.paymentId;
    document.getElementById('receiptOrderId').innerText = AppState.lastReceipt.orderId;
    document.getElementById('receiptTimestamp').innerText = AppState.lastReceipt.timestamp;

    document.getElementById('receiptModal').classList.remove('hidden');
    showToast("Donation captured successfully!", "success");
}

function closeReceiptModal() {
    document.getElementById('receiptModal').classList.add('hidden');
}

function downloadDonationReceipt() {
    if (!AppState.lastReceipt) return;

    const content = `======================================================================
                   IMPACTFUND DONATION RECEIPT
               Cryptographically Verified & Captured
======================================================================

Date & Time         : ${AppState.lastReceipt.timestamp}
Receipt Identifier  : ${AppState.lastReceipt.orderId}
Razorpay Payment ID : ${AppState.lastReceipt.paymentId}

CONTRIBUTION DETAILS:
----------------------------------------------------------------------
Donor Name          : ${AppState.lastReceipt.donorName}
Campaign Backed     : ${AppState.lastReceipt.campaignTitle}
Amount Contributed  : INR ₹${Number(AppState.lastReceipt.amount).toLocaleString('en-IN')}
Transaction Status  : SUCCESS (HMAC-SHA256 Cryptographically Verified)

Thank you for your generous contribution to humanitarian causes!
ImpactFund Crowdfunding Platform (Java 21 & Spring Boot 3 Engine)
======================================================================`;

    const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = `Receipt_${AppState.lastReceipt.paymentId}.txt`;
    link.click();
    URL.revokeObjectURL(url);
}

// ------------------------------------------------------------------------------
// 6. CAMPAIGN CREATION
// ------------------------------------------------------------------------------
function openCreateCampaignModal() {
    if (!AppState.user) {
        showToast("Please sign in to launch a crowdfunding campaign.", "info");
        openAuthModal('login');
        return;
    }
    document.getElementById('createCampaignModal').classList.remove('hidden');
}

function closeCreateCampaignModal() {
    document.getElementById('createCampaignModal').classList.add('hidden');
}

async function handleCreateCampaign(e) {
    e.preventDefault();
    const btn = document.getElementById('btnSubmitCampaign');
    const title = document.getElementById('campTitleInput').value.trim();
    const targetAmount = parseFloat(document.getElementById('campTargetInput').value);
    const description = document.getElementById('campDescInput').value.trim();

    if (!title || !targetAmount || !description) {
        showToast("Please complete all campaign fields.", "error");
        return;
    }

    btn.disabled = true;
    btn.innerText = "Publishing...";

    if (AppState.isMockMode) {
        const newCamp = {
            id: "camp_" + Date.now(),
            title,
            description,
            targetAmount,
            collectedAmount: 0,
            percentageFunded: 0,
            status: "ACTIVE",
            ownerName: AppState.user.name || "Campaign Creator",
            category: "Community"
        };
        AppState.campaigns.unshift(newCamp);
        renderCampaigns(AppState.campaigns);
        updateImpactStats(AppState.campaigns);
        closeCreateCampaignModal();
        showToast("Campaign created successfully (Mock Mode)!", "success");
        btn.disabled = false;
        btn.innerText = "Publish Campaign";
        return;
    }

    try {
        const response = await fetch(`${AppState.apiBase}/api/v1/campaigns`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${AppState.user.token}`
            },
            body: JSON.stringify({ title, description, targetAmount })
        });

        const json = await response.json();
        if (!response.ok || !json.success) {
            throw new Error(json.message || "Failed to create campaign.");
        }

        showToast("Campaign published successfully!", "success");
        closeCreateCampaignModal();
        fetchCampaigns();
    } catch (err) {
        showToast(`Error: ${err.message}`, "error");
    } finally {
        btn.disabled = false;
        btn.innerText = "Publish Campaign";
    }
}

// ------------------------------------------------------------------------------
// 7. AUTHENTICATION & SESSION MANAGEMENT
// ------------------------------------------------------------------------------
function openAuthModal(tab = 'login') {
    switchAuthTab(tab);
    document.getElementById('authModal').classList.remove('hidden');
}

function closeAuthModal() {
    document.getElementById('authModal').classList.add('hidden');
}

function switchAuthTab(tab) {
    const loginForm = document.getElementById('loginForm');
    const registerForm = document.getElementById('registerForm');
    const btnLogin = document.getElementById('tabBtnLogin');
    const btnReg = document.getElementById('tabBtnRegister');

    if (tab === 'login') {
        loginForm.classList.remove('hidden');
        registerForm.classList.add('hidden');
        btnLogin.className = "flex-1 py-4 text-center font-bold text-sm text-emerald-600 border-b-2 border-emerald-600";
        btnReg.className = "flex-1 py-4 text-center font-bold text-sm text-slate-400 hover:text-slate-600 border-b-2 border-transparent";
    } else {
        loginForm.classList.add('hidden');
        registerForm.classList.remove('hidden');
        btnReg.className = "flex-1 py-4 text-center font-bold text-sm text-emerald-600 border-b-2 border-emerald-600";
        btnLogin.className = "flex-1 py-4 text-center font-bold text-sm text-slate-400 hover:text-slate-600 border-b-2 border-transparent";
    }
}

async function handleLogin(e) {
    e.preventDefault();
    const email = document.getElementById('loginEmail').value.trim();
    const password = document.getElementById('loginPassword').value.trim();

    if (AppState.isMockMode) {
        const mockUser = {
            name: email.split('@')[0],
            email,
            token: "mock_jwt_token_" + Date.now(),
            role: "ROLE_USER"
        };
        saveUserSession(mockUser);
        closeAuthModal();
        showToast(`Welcome back, ${mockUser.name}!`, "success");
        return;
    }

    try {
        const response = await fetch(`${AppState.apiBase}/api/v1/auth/login`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ email, password })
        });

        const json = await response.json();
        if (!response.ok || !json.success) {
            throw new Error(json.message || "Invalid email or password.");
        }

        saveUserSession(json.data);
        closeAuthModal();
        showToast("Signed in successfully!", "success");
    } catch (err) {
        showToast(err.message, "error");
    }
}

async function handleRegister(e) {
    e.preventDefault();
    const name = document.getElementById('regName').value.trim();
    const email = document.getElementById('regEmail').value.trim();
    const password = document.getElementById('regPassword').value.trim();
    const role = document.getElementById('regRole').value;

    if (AppState.isMockMode) {
        const mockUser = { name, email, token: "mock_jwt_" + Date.now(), role };
        saveUserSession(mockUser);
        closeAuthModal();
        showToast("Registration successful (Mock Mode)!", "success");
        return;
    }

    try {
        const response = await fetch(`${AppState.apiBase}/api/v1/auth/register`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, email, password, role })
        });

        const json = await response.json();
        if (!response.ok || !json.success) {
            throw new Error(json.message || "Registration failed.");
        }

        saveUserSession(json.data);
        closeAuthModal();
        showToast("Account created successfully!", "success");
    } catch (err) {
        showToast(err.message, "error");
    }
}

function saveUserSession(userData) {
    AppState.user = userData;
    localStorage.setItem('impactfund_user', JSON.stringify(userData));
    initAuthUI();
}

function logoutUser() {
    AppState.user = null;
    localStorage.removeItem('impactfund_user');
    initAuthUI();
    showToast("Signed out successfully.", "info");
}

function initAuthUI() {
    const unauthNav = document.getElementById('unauthNav');
    const authNav = document.getElementById('authNav');
    const userName = document.getElementById('navUserName');
    const userAvatar = document.getElementById('navUserAvatar');
    const dropdownEmail = document.getElementById('dropdownUserEmail');
    const dropdownRole = document.getElementById('dropdownUserRole');

    if (AppState.user) {
        unauthNav.classList.add('hidden');
        authNav.classList.remove('hidden');
        authNav.classList.add('flex');
        
        const initial = (AppState.user.name || AppState.user.email || 'U').charAt(0).toUpperCase();
        userName.innerText = AppState.user.name || AppState.user.email;
        userAvatar.innerText = initial;
        dropdownEmail.innerText = AppState.user.email;
        dropdownRole.innerText = AppState.user.role || 'ROLE_USER';
    } else {
        unauthNav.classList.remove('hidden');
        authNav.classList.add('hidden');
        authNav.classList.remove('flex');
    }
}

function toggleUserDropdown() {
    const dropdown = document.getElementById('userDropdown');
    dropdown.classList.toggle('hidden');
}

// ------------------------------------------------------------------------------
// 8. SEARCH, FILTER & SORT CONTROLS
// ------------------------------------------------------------------------------
function filterCampaigns() {
    const query = document.getElementById('campaignSearchInput').value.toLowerCase();
    const filtered = AppState.campaigns.filter(c => 
        c.title.toLowerCase().includes(query) || 
        c.description.toLowerCase().includes(query)
    );
    renderCampaigns(filtered);
}

function sortCampaigns() {
    const sortVal = document.getElementById('campaignSortSelect').value;
    let sorted = [...AppState.campaigns];

    if (sortVal === 'fundingHigh') {
        sorted.sort((a, b) => (b.percentageFunded || 0) - (a.percentageFunded || 0));
    } else if (sortVal === 'targetHigh') {
        sorted.sort((a, b) => (b.targetAmount || 0) - (a.targetAmount || 0));
    } else {
        // newest first
        sorted.sort((a, b) => new Date(b.createdAt || 0) - new Date(a.createdAt || 0));
    }

    renderCampaigns(sorted);
}

// ------------------------------------------------------------------------------
// 9. API SETTINGS MODAL
// ------------------------------------------------------------------------------
function toggleApiSettingsModal() {
    const modal = document.getElementById('apiSettingsModal');
    modal.classList.toggle('hidden');
}

function openApiSettingsModal() {
    document.getElementById('apiSettingsModal').classList.remove('hidden');
}

function loadApiSettingsUI() {
    const input = document.getElementById('apiEndpointInput');
    const mockCheck = document.getElementById('mockModeCheckbox');
    if (input) input.value = AppState.apiBase;
    if (mockCheck) mockCheck.checked = AppState.isMockMode;
}

function saveApiSettings() {
    const input = document.getElementById('apiEndpointInput');
    const mockCheck = document.getElementById('mockModeCheckbox');

    if (input) {
        const newBase = input.value.trim().replace(/\/+$/, '');
        AppState.apiBase = newBase;
        localStorage.setItem('impactfund_api_base', newBase);
    }

    if (mockCheck) {
        AppState.isMockMode = mockCheck.checked;
        localStorage.setItem('impactfund_mock_mode', mockCheck.checked ? 'true' : 'false');
    }

    toggleApiSettingsModal();
    fetchCampaigns();
    showToast("Settings updated.", "success");
}

// ------------------------------------------------------------------------------
// 10. NOTIFICATION TOAST SYSTEM
// ------------------------------------------------------------------------------
function showToast(message, type = 'info') {
    const container = document.getElementById('toastContainer');
    if (!container) return;

    const toast = document.createElement('div');
    const colorClasses = {
        success: 'bg-emerald-600 text-white',
        error: 'bg-red-600 text-white',
        info: 'bg-slate-900 text-white'
    }[type] || 'bg-slate-900 text-white';

    const icon = {
        success: 'fa-circle-check',
        error: 'fa-circle-exclamation',
        info: 'fa-circle-info'
    }[type] || 'fa-circle-info';

    toast.className = `${colorClasses} p-4 rounded-2xl shadow-xl flex items-center gap-3 text-xs font-semibold pointer-events-auto transform transition duration-300 translate-y-2 opacity-0`;
    toast.innerHTML = `<i class="fa-solid ${icon} text-sm"></i> <span class="flex-1">${escapeHtml(message)}</span>`;

    container.appendChild(toast);

    requestAnimationFrame(() => {
        toast.classList.remove('translate-y-2', 'opacity-0');
    });

    setTimeout(() => {
        toast.classList.add('opacity-0', 'translate-y-2');
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/[&<>'"]/g, tag => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        "'": '&#39;',
        '"': '&quot;'
    }[tag] || tag));
}
