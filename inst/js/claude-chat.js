// shinyClaudeCodeUI — Client-side helpers

(function() {
  'use strict';

  // ── Skill autocomplete ─────────────────────────────────────────────────────
  //
  // Each chat module instance registers its skills via a custom Shiny message.
  // The dropdown div has id = ns("skill_dropdown") and data-chat-ns = ns("chat").

  function initSkillAutocomplete(dropdown) {
    var chatNs   = dropdown.dataset.chatNs;          // e.g. "claude-chat"
    var inputSel = 'shiny-chat-input[id="' + chatNs + '"] textarea';

    function getTextarea() {
      return document.querySelector(inputSel);
    }

    // ── render dropdown items ──────────────────────────────────────────────
    function showDropdown(matches) {
      dropdown.innerHTML = matches.map(function(s) {
        return '<div class="skill-item" data-skill="' + s + '">' +
               '<span class="skill-slash">/</span>' + s + '</div>';
      }).join('');

      dropdown.querySelectorAll('.skill-item').forEach(function(item) {
        item.addEventListener('mouseenter', function() {
          setActive(item);
        });
        item.addEventListener('click', function() {
          completeSkill(item.dataset.skill);
        });
      });

      // Position above the textarea
      var ta = getTextarea();
      if (ta) {
        var rect = ta.getBoundingClientRect();
        dropdown.style.left   = rect.left + 'px';
        dropdown.style.bottom = (window.innerHeight - rect.top + 4) + 'px';
        dropdown.style.width  = rect.width + 'px';
      }
      dropdown.hidden = false;
    }

    function hideDropdown() {
      dropdown.hidden = true;
      dropdown.innerHTML = '';
    }

    function setActive(item) {
      dropdown.querySelectorAll('.skill-item').forEach(function(i) {
        i.classList.remove('active');
      });
      if (item) item.classList.add('active');
    }

    function activeItem() {
      return dropdown.querySelector('.skill-item.active');
    }

    function completeSkill(skillName) {
      var ta = getTextarea();
      if (!ta) return;
      var val = ta.value;
      var slashIdx = val.lastIndexOf('/');
      ta.value = (slashIdx >= 0 ? val.slice(0, slashIdx) : val) + '/' + skillName + ' ';
      ta.dispatchEvent(new Event('input', { bubbles: true }));
      hideDropdown();
      ta.focus();
    }

    // ── textarea events ────────────────────────────────────────────────────
    function attachTextarea() {
      var ta = getTextarea();
      if (!ta) { setTimeout(attachTextarea, 300); return; }

      ta.addEventListener('input', function() {
        var skills = dropdown._skills || [];
        if (!skills.length) { hideDropdown(); return; }

        var val = ta.value;
        var slashIdx = val.lastIndexOf('/');
        // Only activate if slash is in the last 30 chars (avoid matching old text)
        if (slashIdx < 0 || slashIdx < val.length - 30) { hideDropdown(); return; }

        var query   = val.slice(slashIdx + 1).toLowerCase();
        var matches = skills.filter(function(s) {
          return s.toLowerCase().startsWith(query);
        });

        if (matches.length === 0) { hideDropdown(); return; }
        showDropdown(matches);
        // Auto-highlight first item
        var first = dropdown.querySelector('.skill-item');
        if (first) first.classList.add('active');
      });

      ta.addEventListener('keydown', function(e) {
        if (dropdown.hidden) return;
        var items = Array.from(dropdown.querySelectorAll('.skill-item'));
        var cur   = activeItem();
        var idx   = cur ? items.indexOf(cur) : -1;

        if (e.key === 'ArrowDown') {
          e.preventDefault();
          setActive(items[(idx + 1) % items.length]);
        } else if (e.key === 'ArrowUp') {
          e.preventDefault();
          setActive(items[(idx - 1 + items.length) % items.length]);
        } else if (e.key === 'Tab' || e.key === 'Enter') {
          var sel = cur || items[0];
          if (sel) { e.preventDefault(); completeSkill(sel.dataset.skill); }
        } else if (e.key === 'Escape') {
          hideDropdown();
        }
      });
    }
    attachTextarea();

    // Close on outside click
    document.addEventListener('click', function(e) {
      var ta = getTextarea();
      if (!dropdown.hidden && e.target !== ta && !dropdown.contains(e.target)) {
        hideDropdown();
      }
    });
  }

  // Boot all skill dropdowns on the page
  function bootDropdowns() {
    document.querySelectorAll('.skill-autocomplete[data-chat-ns]').forEach(function(el) {
      if (!el._initialized) {
        el._initialized = true;
        initSkillAutocomplete(el);
      }
    });
  }
  document.addEventListener('DOMContentLoaded', bootDropdowns);

  // Expose so R's sendCustomMessage handler can push skills into the right dropdown
  window.shinyClaudeSetSkills = function(dropdownId, skills) {
    var el = document.getElementById(dropdownId);
    if (el) el._skills = skills;
  };

})();
