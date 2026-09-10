// Theme toggle functionality
(function() {
  // Reading localStorage throws outright when the browser blocks site data,
  // and this runs before the rest of the file.
  var storedTheme;
  try {
    storedTheme = localStorage.getItem('resque-theme');
  } catch (e) {
    return;
  }
  if (storedTheme) {
    document.documentElement.setAttribute('data-theme', storedTheme);
  }
})();

$(function() {
  var poll_interval = 2

  // Theme toggle handler
  $('.theme-toggle').click(function() {
    var html = document.documentElement;
    var currentTheme = html.getAttribute('data-theme');
    var prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    var newTheme;

    if (currentTheme === 'dark') {
      newTheme = 'light';
    } else if (currentTheme === 'light') {
      newTheme = 'dark';
    } else {
      // No explicit theme set, toggle from system preference
      newTheme = prefersDark ? 'light' : 'dark';
    }

    html.setAttribute('data-theme', newTheme);
    try {
      localStorage.setItem('resque-theme', newTheme);
    } catch (e) {}
    return false;
  });

  var relatizer = function(){
    var dt = $(this).text(), relatized = $.relatizeDate(this)
    if ($(this).parents("a").length > 0 || $(this).is("a")) {
      $(this).relatizeDate()
      if (!$(this).attr('title')) {
        $(this).attr('title', dt)
      }
    } else {
      $(this)
        .text('')
        .append( $('<a href="#" class="toggle_format" />').attr('title', dt)
        .append( $('<span class="date_time" />').text(dt) )
        .append( $('<span class="relatized_time" />').text(relatized) ) )
    }
  };

  $('.time').each(relatizer);

  $('.time a.toggle_format .date_time').hide()

  var format_toggler = function(){
    $('.time a.toggle_format span').toggle()
    $(this).attr('title', $('span:hidden',this).text())
    return false
  };

  $('.time a.toggle_format').click(format_toggler);

  $('.backtrace').click(function() {
    $(this).next().toggle()
    return false
  })

  $('a[rel=poll]').click(function() {
    var href = $(this).attr('href')
    $(this).parent().text('Starting...')
    $("#main").addClass('polling')

    var poller = function() {
      $.ajax({dataType: 'text', type: 'get', url: href,
        success: function(data) {
          $('#main').html(data)
          $('#main .time').relatizeDate()
          setTimeout(poller, poll_interval * 1000)
        },
        error: function(data) {
          if (data.status == '401') { window.location.href = '/' }
          setTimeout(poller, poll_interval * 1000)
        }
      })
    }

    setTimeout(poller, poll_interval * 1000)

    return false
  })

  $('ul.failed li').hover(function() {
    $(this).addClass('hover');
  }, function() {
    $(this).removeClass('hover');
  })

  $('ul.failed a[rel=retry]').click(function() {
    var href = $(this).attr('href');
    $(this).text('Retrying...');
    var parent = $(this).parent();
    $.ajax({dataType: 'text', type: 'get', url: href, success: function(data) {
      parent.html('Retried <b><span class="time">' + data + '</span></b>');
      relatizer.apply($('.time', parent));
      $('.date_time', parent).hide();
      $('a.toggle_format span', parent).click(format_toggler);
    }});
    return false;
  })
})

