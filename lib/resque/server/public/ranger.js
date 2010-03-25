$(function() {
  var poll_interval = 2

  $('.time').each(function(){
    var dt = $(this).text(), relatized = $.relatizeDate(this)
    if ($(this).parents("a").length > 0 || $(this).is("a")) {
      $(this).relatizeDate()
      if (!$(this).attr('title')) {
        $(this).attr('title', dt)
      }
    } else {
      $(this)
        .text('')
        .append( $('<a href="#" class="toggle_format" title="' + dt + '" />')
        .append('<span class="date_time">' + dt +
                '</span><span class="relatized_time">' +
                relatized + '</span>') )
    }
  })

  $('.time a.toggle_format .date_time').hide()

  $('.time a.toggle_format').click(function(){
    $('.time a.toggle_format span').toggle()
    $(this).attr('title', $('span:hidden',this).text())
    return false
  })

  $('.backtrace').click(function() {
    $(this).next().toggle()
    return false
  })

  $('a[rel=poll]').click(function() {
    var href = $(this).attr('href')
    $(this).parent().text('Starting...')
    $("#main").addClass('polling')

    setInterval(function() {
      $.ajax({dataType: 'text', type: 'get', url: href, success: function(data) {
        $('#main').html(data)
        $('#main .time').relatizeDate()
      }})
    }, poll_interval * 1000)

    return false
  })
})