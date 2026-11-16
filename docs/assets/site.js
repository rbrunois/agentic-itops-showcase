// Theme toggle shared by every page; the initial theme is set inline in <head> to avoid a flash.
(function () {
  var root = document.documentElement;
  var toggle = document.getElementById('themeToggle');
  function syncTheme() {
    var dark = root.getAttribute('data-theme') === 'dark';
    toggle.querySelector('use').setAttribute('href', dark ? '#i-sun' : '#i-moon');
    toggle.setAttribute('aria-label', dark ? 'Switch to light theme' : 'Switch to dark theme');
  }
  toggle.addEventListener('click', function () {
    var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    try { localStorage.setItem('page-theme', next); } catch (e) {}
    syncTheme();
  });
  syncTheme();
})();
