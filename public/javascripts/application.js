$(() => {

  $('button').on('click', (e) => {
    $('.results').html('<ol></ol>');
    var lastResponse = false;

    $.ajax({
      url: '/scan',
      xhrFields: {
        onprogress: (e) => {
          var progressResponse;
          const resp = e.currentTarget.response;
          if (!lastResponse) {
            progressResponse = resp;
          } else {
            progressResponse = resp.substring(lastResponse);
          }
          lastResponse = resp.length;
          $('.results').append(progressResponse);
        }
      },
    }).done((data) => {
      $('.results').append(`<br>Scan complete.`);
    }).fail((error) => {
      $('.results').append(`<br><em style="color: red;">${error}</em><br>`);
    });

  });

});
