# supabase-captchapng
Showing how to port captchapng to PLV8 so it can be used in a PostgreSQL function

## Implementing `captchapng` in PLV8
see:  [captchapng](https://github.com/GeorgeChan/captchapng)

## The function `supabase_captchapng` is created in [supabase_captchapng.sql](./supabase_captchapng.sql)

`supabase_captchapng(digits integer default 4, width integer default 80,height integer default 30)`

Parameters:

- digits: the number of digits to generate for the captcha, default is 4 digits
- width: the number of pixels wide to make resulting image
- height: the number of pixels high to make the resulting image

Output:

Output is a JSON object with 2 properties:
- num: the random number that was generated
- img: a base64-encoded string that can be used in an `img` tag to display the captcha
  - i.e. `<img src="data:image/png;base64, xxxxxxxxxxxxxxxxxxxxxxxxx=="/>
  

