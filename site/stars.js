/**
 * Exact reproduction of Starfield.gd logic
 */
function initStarfield() {
    const canvas = document.createElement('canvas');
    canvas.id = 'starfield-bg';
    document.body.prepend(canvas);

    const ctx = canvas.getContext('2d');
    let width, height;

    const stars = [];
    const numStars = 1000;

    // Box-Muller transform for Gaussian distribution
    function randfn(mean, std) {
        const u1 = 1 - Math.random();
        const u2 = 1 - Math.random();
        const randStdNormal = Math.sqrt(-2.0 * Math.log(u1)) * Math.sin(2.0 * Math.PI * u2);
        return mean + std * randStdNormal;
    }

    function posmod(n, m) {
        return ((n % m) + m) % m;
    }

    function resize() {
        width = window.innerWidth;
        height = window.innerHeight;
        canvas.width = width;
        canvas.height = height;
        generateStars();
        draw();
    }

    function generateStars() {
        stars.length = 0;
        for (let i = 0; i < numStars; i++) {
            const t = Math.random();
            const centerX = t * width;
            const centerY = t * height;

            // Organic Gaussian spread (0.15 of view size per Starfield.gd)
            const sx = posmod(centerX + randfn(0, width * 0.15), width);
            const sy = posmod(centerY + randfn(0, height * 0.15), height);

            const brightness = Math.random();
            // Colors from Starfield.gd: 0.44 (light) or 0.25 (dark)
            const color = brightness > 0.6 ? '#707070' : '#404040';

            stars.append ? null : stars.push({ x: sx, y: sy, color: color });
        }
    }

    function draw() {
        ctx.fillStyle = '#141414'; // Matching default_clear_color
        ctx.fillRect(0, 0, width, height);

        for (const star of stars) {
            ctx.fillStyle = star.color;
            ctx.fillRect(Math.floor(star.x), Math.floor(star.y), 1, 1);
        }
    }

    window.addEventListener('resize', resize);
    resize();
}

initStarfield();
