// We are converting the following code to PLV8 in supabase_captchapng.sql
// const fs = require('fs')
var captchapng = require('captchapng');

const r = 1234; // Math.random()*9000+1000;
var p = new captchapng(80,30,parseInt(r)); // width,height,numeric captcha
        p.color(0, 0, 0, 0);  // First color: background (red, green, blue, alpha)
        p.color(80, 80, 80, 255); // Second color: paint (red, green, blue, alpha)

        var img = p.getBase64();
        var imgbase64 = new Buffer(img,'base64');
       // response.writeHead(200, {
       //     'Content-Type': 'image/png'
       // });

console.log(r);
console.log(img);
