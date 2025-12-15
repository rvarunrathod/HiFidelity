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

// Function to get the appropriate navbar background based on color scheme
function getNavbarBackground(isScrolled) {
    const isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    
    if (isDark) {
        return isScrolled ? 'rgba(28, 28, 30, 0.9)' : 'rgba(28, 28, 30, 0.7)';
    } else {
        return isScrolled ? 'rgba(255, 255, 255, 0.9)' : 'rgba(255, 255, 255, 0.7)';
    }
}

function updateNavbarStyle() {
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
    const isScrolled = scrollTop > 20;
    
    navbar.style.background = getNavbarBackground(isScrolled);
    navbar.style.boxShadow = isScrolled ? '0 1px 0 rgba(0, 0, 0, 0.1)' : 'none';
    
    lastScrollTop = scrollTop;
}

window.addEventListener('scroll', updateNavbarStyle);

// Listen for color scheme changes
window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', updateNavbarStyle);

// Initialize navbar style
updateNavbarStyle();

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

