// shinyClaudeCodeUI — Client-side helpers
// Currently minimal; will expand for diff rendering, code highlighting, etc.

(function() {
  'use strict';

  // Auto-scroll chat to bottom when new content arrives
  // shinychat handles this internally, but we add smooth scrolling
  if (window.MutationObserver) {
    document.addEventListener('DOMContentLoaded', function() {
      var chatAreas = document.querySelectorAll('.claude-chat-area');
      chatAreas.forEach(function(area) {
        var observer = new MutationObserver(function() {
          var scrollable = area.querySelector('[data-scroll-container]') ||
                          area.querySelector('.chat-messages');
          if (scrollable) {
            scrollable.scrollTop = scrollable.scrollHeight;
          }
        });
        observer.observe(area, { childList: true, subtree: true });
      });
    });
  }
})();
