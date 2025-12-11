// Smooth scroll with offset for fixed navbar
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const targetId = this.getAttribute('href');
        if (targetId === '#') return;
        
        const targetElement = document.querySelector(targetId);
        if (targetElement) {
            const navbarHeight = document.querySelector('.navbar').offsetHeight;
            const targetPosition = targetElement.offsetTop - navbarHeight;
            
            window.scrollTo({
                top: targetPosition,
                behavior: 'smooth'
            });
        }
    });
});

// Page load animation
document.addEventListener('DOMContentLoaded', () => {
    document.body.style.opacity = '0';
    setTimeout(() => {
        document.body.style.transition = 'opacity 0.8s ease';
        document.body.style.opacity = '1';
    }, 100);
});

// Navbar background on scroll
let lastScrollTop = 0;
const navbar = document.querySelector('.navbar');

window.addEventListener('scroll', () => {
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
    
    // Add shadow/background when scrolled
    if (scrollTop > 20) {
        navbar.style.background = 'rgba(0, 0, 0, 0.8)';
        navbar.style.boxShadow = '0 1px 0 rgba(255, 255, 255, 0.1)';
    } else {
        navbar.style.background = 'rgba(0, 0, 0, 0.6)';
        navbar.style.boxShadow = 'none';
    }
    
    lastScrollTop = scrollTop;
});

// Copy code on click
document.querySelectorAll('.code-block').forEach(block => {
    block.style.cursor = 'pointer';
    block.title = 'Click to copy';
    
    block.addEventListener('click', async () => {
        const codes = block.querySelectorAll('code');
        const textToCopy = Array.from(codes).map(code => code.textContent).join('\n');
        
        try {
            await navigator.clipboard.writeText(textToCopy);
            
            // Visual feedback
            const originalBg = block.style.backgroundColor;
            block.style.backgroundColor = 'rgba(48, 209, 88, 0.2)';
            block.style.transition = 'background-color 0.3s ease';
            
            setTimeout(() => {
                block.style.backgroundColor = originalBg;
            }, 300);
        } catch (err) {
            console.error('Failed to copy:', err);
        }
    });
});

