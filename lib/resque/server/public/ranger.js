$(function() {
  $('.time').relatizeDate()
  $('.backtrace').click(function() {
    $(this).next().toggle()
    return false
  })
})