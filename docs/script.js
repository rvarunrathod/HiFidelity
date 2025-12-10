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

// Page load animation (simplified - no scroll animations)
document.addEventListener('DOMContentLoaded', () => {
    // Add page load animation only
    document.body.style.opacity = '0';
    setTimeout(() => {
        document.body.style.transition = 'opacity 0.5s ease';
        document.body.style.opacity = '1';
    }, 100);

    // Initialize showcase slider
    initShowcaseSlider();
    
    // Initialize lightbox
    initLightbox();
});

// Showcase Slider
function initShowcaseSlider() {
    const track = document.getElementById('showcaseTrack');
    const prevBtn = document.getElementById('prevBtn');
    const nextBtn = document.getElementById('nextBtn');

    if (!track || !prevBtn || !nextBtn) return;

    const items = track.querySelectorAll('.showcase-item');
    let currentIndex = 0;

    function showSlide(index) {
        // Loop around
        if (index < 0) {
            index = items.length - 1;
        } else if (index >= items.length) {
            index = 0;
        }
        
        currentIndex = index;
        
        // Update transform to show current slide
        const offset = -currentIndex * 100;
        track.style.transform = `translateX(${offset}%)`;
        
        // Update active state
        items.forEach((item, i) => {
            if (i === currentIndex) {
                item.classList.add('active');
            } else {
                item.classList.remove('active');
            }
        });
    }

    prevBtn.addEventListener('click', () => {
        showSlide(currentIndex - 1);
        stopAutoPlay();
    });

    nextBtn.addEventListener('click', () => {
        showSlide(currentIndex + 1);
        stopAutoPlay();
    });

    // Keyboard navigation
    document.addEventListener('keydown', (e) => {
        if (e.key === 'ArrowLeft') {
            showSlide(currentIndex - 1);
            stopAutoPlay();
        } else if (e.key === 'ArrowRight') {
            showSlide(currentIndex + 1);
            stopAutoPlay();
        }
    });

    // Auto-play
    let autoPlayInterval;
    
    function startAutoPlay() {
        autoPlayInterval = setInterval(() => {
            showSlide(currentIndex + 1);
        }, 5000);
    }

    function stopAutoPlay() {
        clearInterval(autoPlayInterval);
    }

    // Pause auto-play on hover
    const slider = document.querySelector('.showcase-slider');
    if (slider) {
        slider.addEventListener('mouseenter', stopAutoPlay);
        slider.addEventListener('mouseleave', startAutoPlay);
    }

    // Initialize first slide
    showSlide(0);
    
    // Start auto-play
    startAutoPlay();
}

// Navbar background on scroll
let lastScrollTop = 0;
const navbar = document.querySelector('.navbar');

window.addEventListener('scroll', () => {
    const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
    
    if (scrollTop > 50) {
        navbar.classList.add('scrolled');
    } else {
        navbar.classList.remove('scrolled');
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
            block.style.backgroundColor = '#e6f4ea';
            block.style.transition = 'background-color 0.3s ease';
            
            setTimeout(() => {
                block.style.backgroundColor = originalBg;
            }, 300);
        } catch (err) {
            console.error('Failed to copy:', err);
        }
    });
});

// Lazy loading for images
if ('loading' in HTMLImageElement.prototype) {
    const images = document.querySelectorAll('img[loading="lazy"]');
    images.forEach(img => {
        img.src = img.src;
    });
} else {
    // Fallback for browsers that don't support lazy loading
    const script = document.createElement('script');
    script.src = 'https://cdnjs.cloudflare.com/ajax/libs/lazysizes/5.3.2/lazysizes.min.js';
    document.body.appendChild(script);
}

// Parallax effect for hero image
const heroImage = document.querySelector('.hero-image');
if (heroImage) {
    let ticking = false;
    window.addEventListener('scroll', () => {
        if (!ticking) {
            window.requestAnimationFrame(() => {
                const scrolled = window.pageYOffset;
                const rate = scrolled * 0.2;
                heroImage.style.transform = `translateY(${rate}px)`;
                ticking = false;
            });
            ticking = true;
        }
    });
}

// Add mouse move parallax effect to hero
const hero = document.querySelector('.hero');
if (hero && window.innerWidth > 1068) {
    hero.addEventListener('mousemove', (e) => {
        const { clientX, clientY } = e;
        const { offsetWidth, offsetHeight } = hero;
        
        const xPos = (clientX / offsetWidth - 0.5) * 20;
        const yPos = (clientY / offsetHeight - 0.5) * 20;
        
        if (heroImage) {
            heroImage.style.transform = `translate(${xPos}px, ${yPos}px)`;
        }
    });

    hero.addEventListener('mouseleave', () => {
        if (heroImage) {
            heroImage.style.transform = 'translate(0, 0)';
        }
    });
}



// Lightbox functionality
function initLightbox() {
    const lightbox = document.getElementById('lightbox');
    const lightboxImage = document.getElementById('lightboxImage');
    const lightboxCaption = document.getElementById('lightboxCaption');
    const lightboxClose = document.getElementById('lightboxClose');
    const showcaseItems = document.querySelectorAll('.showcase-item');

    if (!lightbox || !lightboxImage || !lightboxClose) return;

    // Add click handler to all showcase items
    showcaseItems.forEach(item => {
        const img = item.querySelector('img');
        const caption = item.querySelector('.showcase-caption');
        
        if (img) {
            img.addEventListener('click', (e) => {
                e.stopPropagation();
                openLightbox(img, caption);
            });
        }
    });

    function openLightbox(img, caption) {
        lightboxImage.src = img.src;
        lightboxImage.alt = img.alt;
        
        if (caption) {
            const title = caption.querySelector('h4')?.textContent || '';
            const desc = caption.querySelector('p')?.textContent || '';
            lightboxCaption.innerHTML = `<h4>${title}</h4><p>${desc}</p>`;
        }
        
        lightbox.classList.add('active');
        document.body.style.overflow = 'hidden';
    }

    function closeLightbox() {
        lightbox.classList.remove('active');
        document.body.style.overflow = '';
    }

    // Close button
    lightboxClose.addEventListener('click', closeLightbox);

    // Close on backdrop click
    lightbox.addEventListener('click', (e) => {
        if (e.target === lightbox || e.target.classList.contains('lightbox-backdrop')) {
            closeLightbox();
        }
    });

    // Close on Escape key
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && lightbox.classList.contains('active')) {
            closeLightbox();
        }
    });
}

// Performance optimization: Debounce scroll events
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// Apply debounce to scroll-heavy operations
const optimizedScroll = debounce(() => {
    // Scroll operations here
}, 10);

window.addEventListener('scroll', optimizedScroll);

