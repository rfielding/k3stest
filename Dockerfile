FROM gcr.io/google-samples/gb-frontend:v4

WORKDIR /var/www/html
ADD controllers.js controllers.js
ADD index.html index.html
ADD guestbook.php guestbook.php

