document.addEventListener('DOMContentLoaded', () => {
    const images = [...document.querySelectorAll('.rst-content img')].filter((img) => {
        const link = img.closest('a');
        return !link || link.classList.contains('image-reference');
    });
    if (!images.length) return;

    const viewer = document.createElement('dialog');
    viewer.className = 'image-viewer';
    viewer.setAttribute('aria-label', '图片大图预览');
    const enlarged = document.createElement('img');
    const hint = document.createElement('p');
    hint.textContent = '点击任意位置或按 Esc 返回';
    viewer.append(enlarged, hint);
    document.body.appendChild(viewer);

    let original;
    const open = (img) => {
        original = img;
        enlarged.src = img.currentSrc || img.src;
        enlarged.alt = img.alt;
        viewer.showModal();
        document.documentElement.classList.add('image-viewer-open');
    };
    viewer.addEventListener('click', () => viewer.close());
    viewer.addEventListener('close', () => {
        document.documentElement.classList.remove('image-viewer-open');
        enlarged.removeAttribute('src');
        original?.focus({ preventScroll: true });
    });

    images.forEach((img) => {
        img.classList.add('image-viewer-trigger');
        img.tabIndex = 0;
        img.setAttribute('role', 'button');
        img.setAttribute('aria-haspopup', 'dialog');
        img.setAttribute('aria-label', `查看大图：${img.alt || '图片'}`);
        img.title = '点击查看大图';
        img.addEventListener('click', (event) => {
            event.preventDefault();
            open(img);
        });
        img.addEventListener('keydown', (event) => {
            if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                open(img);
            }
        });
    });
});
