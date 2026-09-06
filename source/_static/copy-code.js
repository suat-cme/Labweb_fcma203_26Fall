document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('.highlight pre').forEach((pre) => {
        const container = pre.closest('.literal-block-wrapper') || pre.closest('.highlight');

        if (!container || container.querySelector('.copy-code-button')) {
            return;
        }

        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'copy-code-button';
        button.textContent = 'Copy';
        button.setAttribute('aria-label', 'Copy code');
        button.title = 'Copy code';

        button.addEventListener('click', async () => {
            const code = pre.cloneNode(true);
            code.querySelectorAll('.linenos').forEach((lineNumber) => lineNumber.remove());

            try {
                await navigator.clipboard.writeText(code.textContent);
                button.textContent = 'Copied';
                button.classList.add('is-copied');
            } catch {
                button.textContent = 'Copy failed';
            }

            window.setTimeout(() => {
                button.textContent = 'Copy';
                button.classList.remove('is-copied');
            }, 1500);
        });

        container.appendChild(button);
    });
});
