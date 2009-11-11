var poll_interval = 2;

$(function() {

  $('.time').relatizeDate()
  $('.backtrace').click(function() {
    $(this).next().toggle()
    return false
  })
  
  $('a[rel=poll]').click(function() {
    var href = $(this).attr('href')
    $(this).parent().text('Starting...')
    $("#main").addClass('polling')
    setInterval(function() {
      $.ajax({dataType:'text', type:'get', url:href, success:function(data) { 
        $('#main').html(data) 
        $('#main .time').relatizeDate()
      }})
    }, poll_interval * 1000)
    return false
  })
    
})