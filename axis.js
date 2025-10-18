function openMap(){
    window.open(
        "https://www.gpsvisualizer.com/display/map/20251018070808-63094-map.html",
        "_blank"
    );
}

// cursor-glow + parallax
(() => {
    const panel = document.getElementById('panel');
    const root  = document.documentElement;

    window.addEventListener('mousemove', (e) => {
        const xPct = (e.clientX / window.innerWidth)  * 100;
        const yPct = (e.clientY / window.innerHeight) * 100;

        root.style.setProperty('--mx', `${xPct}%`);
        root.style.setProperty('--my', `${yPct}%`);

        const tiltX = (0.5 - yPct/100) * 8;
        const tiltY = (xPct/100 - 0.5) * 8;
        panel.style.transform = `translateY(-10px) rotateX(${tiltX}deg) rotateY(${tiltY}deg)`;
    });

    window.addEventListener('mouseleave', () => { panel.style.transform = ''; });
})();
