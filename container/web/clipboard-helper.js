(() => {
    'use strict';

    function installClipboardButton() {
        const field = document.getElementById('noVNC_clipboard_text');
        if (!field || document.getElementById('remote_clipboard_copy')) return;

        const controls = document.createElement('div');
        const hint = document.createElement('p');
        hint.textContent = 'Im entfernten Firefox mit Strg+C kopieren (auch am Mac). Danach hier auf diesen Rechner übernehmen. Nur Text wird übertragen.';
        const button = document.createElement('button');
        button.id = 'remote_clipboard_copy';
        button.type = 'button';
        button.textContent = 'Auf diesen Rechner kopieren';
        const status = document.createElement('p');
        status.setAttribute('role', 'status');
        status.setAttribute('aria-live', 'polite');
        controls.append(hint, button, status);
        field.insertAdjacentElement('afterend', controls);

        button.addEventListener('click', async () => {
            const text = field.value;
            if (!text) {
                status.textContent = 'Noch kein Text empfangen. Zuerst im entfernten Firefox Strg+C drücken.';
                return;
            }
            try {
                await navigator.clipboard.writeText(text);
                status.textContent = 'Kopiert. Du kannst den Text jetzt auf diesem Rechner einfügen.';
            } catch {
                // A denied/missing Clipboard API still leaves an explicit manual path.
                field.focus();
                field.select();
                let copied = false;
                try { copied = document.execCommand('copy'); } catch { /* manual fallback */ }
                status.textContent = copied
                    ? 'Kopiert. Du kannst den Text jetzt auf diesem Rechner einfügen.'
                    : 'Text ist markiert. Jetzt am Mac ⌘C drücken, unter Windows/Linux Strg+C.';
            }
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', installClipboardButton, { once: true });
    } else {
        installClipboardButton();
    }
})();
