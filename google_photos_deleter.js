// ...existing code...
// How many photos to delete?
// Put a number value, like this
// const maxImageCount = 5896
const maxImageCount = "ALL_PHOTOS";

// Selector for Images and buttons
const ELEMENT_SELECTORS = {
    checkboxClass: '.ckGgle',
    languageAgnosticDeleteButton: 'div[data-delete-origin] button',
    deleteButton: 'button[aria-label="Delete"]',
    confirmationButton: 'div[aria-modal="true"] > div > div > div > button:nth-of-type(2)'
}

// Time Configuration (in milliseconds)
const TIME_CONFIG = {
    delete_cycle: 10000,
    press_button_delay: 2000,
    selector_retry_delay: 1000
};

const MAX_RETRIES = 1000;

let imageCount = 0;

function sleep(ms) {
    return new Promise(res => setTimeout(res, ms));
}

async function queryWithRetries(selector, retries = MAX_RETRIES, delay = TIME_CONFIG.selector_retry_delay) {
    let attempt = 0;
    let el = null;
    while (attempt++ < retries) {
        el = document.querySelector(selector);
        if (el) return el;
        await sleep(delay);
    }
    return null;
}

async function queryAllWithRetries(selector, retries = MAX_RETRIES, delay = TIME_CONFIG.selector_retry_delay) {
    let attempt = 0;
    let nodes = [];
    while (attempt++ < retries) {
        nodes = document.querySelectorAll(selector);
        if (nodes && nodes.length > 0) return Array.from(nodes);
        await sleep(delay);
    }
    return [];
}

async function runDeletion() {
    const numericLimit = (maxImageCount !== "ALL_PHOTOS") ? parseInt(maxImageCount, 10) : null;

    while (true) {
        // Find checkboxes with retries
        const checkboxes = await queryAllWithRetries(ELEMENT_SELECTORS.checkboxClass);
        if (!checkboxes || checkboxes.length === 0) {
            console.log("[INFO] No more images to delete.");
            console.log("[SUCCESS] Tool exited.");
            return;
        }

        // Decide how many to select this cycle (respect maxImageCount)
        let toSelect = checkboxes.length;
        if (numericLimit !== null) {
            const remaining = numericLimit - imageCount;
            if (remaining <= 0) {
                console.log(`${imageCount} photos deleted as requested`);
                console.log("[SUCCESS] Tool exited.");
                return;
            }
            toSelect = Math.min(toSelect, remaining);
        }

        // Click the first `toSelect` checkboxes
        for (let i = 0; i < toSelect; i++) {
            try { checkboxes[i].click(); }
            catch (e) { /* ignore single click failure, continue */ }
        }
        console.log("[INFO] Selected", toSelect, "images to delete");

        // Wait for UI to update
        await sleep(TIME_CONFIG.press_button_delay);

        // Find and click delete button (try language-agnostic first, fallback to aria-label)
        let delBtn = document.querySelector(ELEMENT_SELECTORS.languageAgnosticDeleteButton);
        if (!delBtn) delBtn = document.querySelector(ELEMENT_SELECTORS.deleteButton);
        if (!delBtn) {
            console.log("[ERROR] Delete button not found. Aborting.");
            return;
        }

        try { delBtn.click(); }
        catch (e) {
            console.log("[ERROR] Failed to click delete button:", e);
            return;
        }

        // Wait for confirmation dialog to appear
        await sleep(TIME_CONFIG.press_button_delay);

        const confirmBtn = await queryWithRetries(ELEMENT_SELECTORS.confirmationButton, 10, 500);
        if (!confirmBtn) {
            console.log("[ERROR] Confirmation button not found. Aborting.");
            return;
        }

        try { confirmBtn.click(); }
        catch (e) {
            console.log("[ERROR] Failed to click confirmation button:", e);
            return;
        }

        imageCount += toSelect;
        console.log(`[INFO] ${imageCount}/${maxImageCount} Deleted`);

        if (numericLimit !== null && imageCount >= numericLimit) {
            console.log(`${imageCount} photos deleted as requested`);
            console.log("[SUCCESS] Tool exited.");
            return;
        }

        // Wait before next cycle to avoid overlapping operations
        await sleep(TIME_CONFIG.delete_cycle);
    }
}

runDeletion();
// ...existing code...