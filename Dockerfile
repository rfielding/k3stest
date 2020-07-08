FROM gcr.io/google-samples/gb-frontend:v4

WORKDIR /var/www/html
ADD guestbook/controllers.js controllers.js
ADD guestbook/index.html index.html
ADD guestbook/guestbook.php guestbook.php

