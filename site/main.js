// Modern Godot 4 Loader with Auto-Path Detection
const GODOT_CONFIG = {
    "args": [],
    "canvasResizePolicy": 2, // MANDATORY: FILL PARENT
    "executable": "asteroids_versus",
    "fscache": true,
    "gdextensionLibs": [],
};

// Check for requirements and SharedArrayBuffer (COOP/COEP)
const VERSION = "2.2"; // Cache-busting version

(function () {
    const loadingOverlay = document.getElementById('loading-overlay');
    const statusText = document.querySelector('.loader-text');

    const updateStatus = (text, isError = false) => {
        const fullText = `[v${VERSION}] ${text}`;
        if (statusText) {
            statusText.textContent = fullText;
            if (isError) statusText.style.color = "#ff5555";
        }
        console.log(`[Godot] ${fullText}`);
    };

    // Wait for everything to be ready
    window.addEventListener('load', () => {
        setTimeout(startEngine, 500); // Small buffer for Service Worker
    });

    async function startEngine() {
        if (typeof Engine === 'undefined') {
            updateStatus("ERROR: ENGINE_SCRIPT_NOT_FOUND", true);
            statusText.innerHTML = `ERROR: v${VERSION} ENGINE_NOT_FOUND<br><small>Check console for script errors.</small>`;
            return;
        }

        const engine = new Engine(GODOT_CONFIG);
        const isIsolated = window.crossOriginIsolated;

        if (!isIsolated) {
            updateStatus("NOTICE: RE-TRYING_ISOLATION...");
            // The Service Worker will reload the page automatically if it can.
            // If it doesn't, we show a helpful error.
        }

        updateStatus("INITIALIZING...");

        try {
            await engine.init("asteroids_versus");
            updateStatus("LOADING DATA...");
            await engine.startGame({
                "onProgress": (current, total) => {
                    if (total > 0) {
                        const percent = Math.round((current / total) * 100);
                        updateStatus(`LOADING: ${percent}%`);
                    }
                }
            });
            updateStatus("READY");
            if (loadingOverlay) {
                loadingOverlay.style.opacity = '0';
                setTimeout(() => loadingOverlay.style.display = 'none', 500);
            }
        } catch (err) {
            console.error(err);
            let detail = isIsolated ? "Engine Error (Check Console)" : "Security Isolation Failed (Refresh Required)";
            updateStatus("ERROR: BOOT_FAILED", true);
            statusText.innerHTML = `ERROR: v${VERSION} BOOT_FAILED<br><small>${detail}</small>`;
        }
    }
})();
