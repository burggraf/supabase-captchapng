create extension if not exists plv8; -- plv8 is required!
drop function if exists supabase_captchapng;
create or replace function public.supabase_captchapng(digits integer default 4, width integer default 80,height integer default 30)
   returns JSON language plv8 as
$$
const pnglib = function(width,height,depth) {


    // helper functions for that ctx
    function write(buffer, offs) {
        for (var i = 2; i < arguments.length; i++) {
            for (var j = 0; j < arguments[i].length; j++) {
                buffer[offs++] = arguments[i].charAt(j);
            }
        }
    }

    function byte2(w) {
        return String.fromCharCode((w >> 8) & 255, w & 255);
    }

    function byte4(w) {
        return String.fromCharCode((w >> 24) & 255, (w >> 16) & 255, (w >> 8) & 255, w & 255);
    }

    function byte2lsb(w) {
        return String.fromCharCode(w & 255, (w >> 8) & 255);
    }

    this.width   = width;
    this.height  = height;
    this.depth   = depth;

    // pixel data and row filter identifier size
    this.pix_size = height * (width + 1);

    // deflate header, pix_size, block headers, adler32 checksum
    this.data_size = 2 + this.pix_size + 5 * Math.floor((0xfffe + this.pix_size) / 0xffff) + 4;

    // offsets and sizes of Png chunks
    this.ihdr_offs = 0;									// IHDR offset and size
    this.ihdr_size = 4 + 4 + 13 + 4;
    this.plte_offs = this.ihdr_offs + this.ihdr_size;	// PLTE offset and size
    this.plte_size = 4 + 4 + 3 * depth + 4;
    this.trns_offs = this.plte_offs + this.plte_size;	// tRNS offset and size
    this.trns_size = 4 + 4 + depth + 4;
    this.idat_offs = this.trns_offs + this.trns_size;	// IDAT offset and size
    this.idat_size = 4 + 4 + this.data_size + 4;
    this.iend_offs = this.idat_offs + this.idat_size;	// IEND offset and size
    this.iend_size = 4 + 4 + 4;
    this.buffer_size  = this.iend_offs + this.iend_size;	// total PNG size

    this.buffer  = new Array();
    this.palette = new Object();
    this.pindex  = 0;

    var _crc32 = new Array();

    // initialize buffer with zero bytes
    for (var i = 0; i < this.buffer_size; i++) {
        this.buffer[i] = "\x00";
    }

    // initialize non-zero elements
    write(this.buffer, this.ihdr_offs, byte4(this.ihdr_size - 12), 'IHDR', byte4(width), byte4(height), "\x08\x03");
    write(this.buffer, this.plte_offs, byte4(this.plte_size - 12), 'PLTE');
    write(this.buffer, this.trns_offs, byte4(this.trns_size - 12), 'tRNS');
    write(this.buffer, this.idat_offs, byte4(this.idat_size - 12), 'IDAT');
    write(this.buffer, this.iend_offs, byte4(this.iend_size - 12), 'IEND');

    // initialize deflate header
    var header = ((8 + (7 << 4)) << 8) | (3 << 6);
    header+= 31 - (header % 31);

    write(this.buffer, this.idat_offs + 8, byte2(header));

    // initialize deflate block headers
    for (var i = 0; (i << 16) - 1 < this.pix_size; i++) {
        var size, bits;
        if (i + 0xffff < this.pix_size) {
            size = 0xffff;
            bits = "\x00";
        } else {
            size = this.pix_size - (i << 16) - i;
            bits = "\x01";
        }
        write(this.buffer, this.idat_offs + 8 + 2 + (i << 16) + (i << 2), bits, byte2lsb(size), byte2lsb(~size));
    }

    /* Create crc32 lookup table */
    for (var i = 0; i < 256; i++) {
        var c = i;
        for (var j = 0; j < 8; j++) {
            if (c & 1) {
                c = -306674912 ^ ((c >> 1) & 0x7fffffff);
            } else {
                c = (c >> 1) & 0x7fffffff;
            }
        }
        _crc32[i] = c;
    }

    // compute the index into a png for a given pixel
    this.index = function(x,y) {
        var i = y * (this.width + 1) + x + 1;
        var j = this.idat_offs + 8 + 2 + 5 * Math.floor((i / 0xffff) + 1) + i;
        return j;
    }

    // convert a color and build up the palette
    this.color = function(red, green, blue, alpha) {

        alpha = alpha >= 0 ? alpha : 255;
        var color = (((((alpha << 8) | red) << 8) | green) << 8) | blue;

        if (typeof this.palette[color] == "undefined") {
            if (this.pindex == this.depth) return "\x00";

            var ndx = this.plte_offs + 8 + 3 * this.pindex;

            this.buffer[ndx + 0] = String.fromCharCode(red);
            this.buffer[ndx + 1] = String.fromCharCode(green);
            this.buffer[ndx + 2] = String.fromCharCode(blue);
            this.buffer[this.trns_offs+8+this.pindex] = String.fromCharCode(alpha);

            this.palette[color] = String.fromCharCode(this.pindex++);
        }
        return this.palette[color];
    }

    // output a PNG string, Base64 encoded
    this.getBase64 = function() {

        var s = this.getDump();

        var ch = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
        var c1, c2, c3, e1, e2, e3, e4;
        var l = s.length;
        var i = 0;
        var r = "";

        do {
            c1 = s.charCodeAt(i);
            e1 = c1 >> 2;
            c2 = s.charCodeAt(i+1);
            e2 = ((c1 & 3) << 4) | (c2 >> 4);
            c3 = s.charCodeAt(i+2);
            if (l < i+2) { e3 = 64; } else { e3 = ((c2 & 0xf) << 2) | (c3 >> 6); }
            if (l < i+3) { e4 = 64; } else { e4 = c3 & 0x3f; }
            r+= ch.charAt(e1) + ch.charAt(e2) + ch.charAt(e3) + ch.charAt(e4);
        } while ((i+= 3) < l);
        return r;
    }

    // output a PNG string
    this.getDump = function() {

        // compute adler32 of output pixels + row filter bytes
        var BASE = 65521; /* largest prime smaller than 65536 */
        var NMAX = 5552;  /* NMAX is the largest n such that 255n(n+1)/2 + (n+1)(BASE-1) <= 2^32-1 */
        var s1 = 1;
        var s2 = 0;
        var n = NMAX;

        for (var y = 0; y < this.height; y++) {
            for (var x = -1; x < this.width; x++) {
                s1+= this.buffer[this.index(x, y)].charCodeAt(0);
                s2+= s1;
                if ((n-= 1) == 0) {
                    s1%= BASE;
                    s2%= BASE;
                    n = NMAX;
                }
            }
        }
        s1%= BASE;
        s2%= BASE;
        write(this.buffer, this.idat_offs + this.idat_size - 8, byte4((s2 << 16) | s1));

        // compute crc32 of the PNG chunks
        function crc32(png, offs, size) {
            var crc = -1;
            for (var i = 4; i < size-4; i += 1) {
                crc = _crc32[(crc ^ png[offs+i].charCodeAt(0)) & 0xff] ^ ((crc >> 8) & 0x00ffffff);
            }
            write(png, offs+size-4, byte4(crc ^ -1));
        }

        crc32(this.buffer, this.ihdr_offs, this.ihdr_size);
        crc32(this.buffer, this.plte_offs, this.plte_size);
        crc32(this.buffer, this.trns_offs, this.trns_size);
        crc32(this.buffer, this.idat_offs, this.idat_size);
        crc32(this.buffer, this.iend_offs, this.iend_size);

        // convert PNG to string
        return "\211PNG\r\n\032\n"+this.buffer.join('');
    }
};

this.numMask = [];
this.numMask[0]=[];
this.numMask[0]=loadNumMask0();
this.numMask[1]=loadNumMask1();
myself = this;

function loadNumMask0() {
    var numbmp=[];
    numbmp[0]=["0011111000","0111111110","0111111110","1110001111","1110001111","1110001111","1110001111","1110001111","1110001111","1110001111","1110001111","1110001111","1110001111","1110001111","1110001111","1110001111","0111111111"," 111111110","0011111100"];
    numbmp[1]=["0000011","0000111","0011111","1111111","1111111","0001111","0001111","0001111","0001111","0001111","0001111","0001111","0001111","0001111","0001111","0001111","0001111","0001111","0001111"];
    numbmp[2]=["001111100","011111110","111111111","111001111","111001111","111001111","111001111","000011111","000011110","000111110","000111100","000111100","001111000","001111000","011110000","011110000","111111111","111111111","111111111"];
    numbmp[3]=["0011111100","0111111110","1111111111","1111001111","1111001111","1111001111","0000001111","0001111110","0001111100","0001111111","0000001111","1111001111","1111001111","1111001111","1111001111","1111001111","1111111111","0111111110","0011111100"];
    numbmp[4]=["00001111110","00001111110","00011111110","00011111110","00011111110","00111011110","00111011110","00111011110","01110011110","01110011110","01110011110","11100011110","11111111111","11111111111","11111111111","11111111111","00000011110","00000011110","00000011110"];
    numbmp[5]=["1111111111","1111111111","1111111111","1111000000","1111000000","1111011100","1111111110","1111111111","1111001111","1111001111","0000001111","0000001111","1111001111","1111001111","1111001111","1111001111","1111111111","0111111110","0011111100"];
    numbmp[6]=["0011111100","0111111110","0111111111","1111001111","1111001111","1111000000","1111011100","1111111110","1111111111","1111001111","1111001111","1111001111","1111001111","1111001111","1111001111","1111001111","0111111111","0111111110","0011111100"];
    numbmp[7]=["11111111","11111111","11111111","00001111","00001111","00001111","00001110","00001110","00011110","00011110","00011110","00011100","00111100","00111100","00111100","00111100","00111000","01111000","01111000"];
    numbmp[8]=["0011111100","0111111110","1111111111","1111001111","1111001111","1111001111","1111001111","0111111110","0011111100","0111111110","1111001111","1111001111","1111001111","1111001111","1111001111","1111001111","1111111111","0111111110","0011111100"];
    numbmp[9]=["0011111100","0111111110","1111111111","1111001111","1111001111","1111001111","1111001111","1111001111","1111001111","1111001111","1111111111","0111111111","0011101111","0000001111","1111001111","1111001111","1111111110","0111111110","0011111000"];

    return numbmp;
}

function loadNumMask1() {
    var numbmp=[];
    numbmp[0] = ["000000001111000","000000111111110","000001110000110","000011000000011","000110000000011","001100000000011","011100000000011","011000000000011","111000000000110","110000000000110","110000000001110","110000000001100","110000000011000","110000000111000","011000011110000","011111111000000","000111110000000"];
    numbmp[1] = ["00000111","00001111","00011110","00010110","00001100","00001100","00011000","00011000","00110000","00110000","00110000","01100000","01100000","01100000","11000000","11000000","11000000"];
    numbmp[2] = ["00000011111000","00001111111110","00011100000110","00011000000011","00000000000011","00000000000011","00000000000011","00000000000110","00000000001110","00000000011100","00000001110000","00000111100000","00001110000000","00111100000000","01110000000000","11111111110000","11111111111110","00000000011110"];
    numbmp[3] = ["000000111111000","000011111111110","000111100000111","000110000000011","000000000000011","000000000000011","000000000001110","000000111111000","000000111111000","000000000011100","000000000001100","000000000001100","110000000001100","111000000011100","111100000111000","001111111110000","000111111000000"];
    numbmp[4] = ["00000011000001","00000110000011","00001100000010","00011000000110","00111000000110","00110000001100","01100000001100","01100000001000","11000000011000","11111111111111","11111111111111","00000000110000","00000000110000","00000000100000","00000001100000","00000001100000","00000001100000"];
    numbmp[5] = ["0000001111111111","0000011111111111","0000111000000000","0000110000000000","0000110000000000","0001110000000000","0001101111100000","0001111111111000","0001110000011000","0000000000001100","0000000000001100","0000000000001100","1100000000001100","1110000000011000","1111000001111000","0111111111100000","0001111110000000"];
    numbmp[6] = ["000000001111100","000000111111110","000011110000111","000111000000011","000110000000000","001100000000000","011001111100000","011111111111000","111110000011000","111000000001100","110000000001100","110000000001100","110000000001100","111000000011000","011100001110000","001111111100000","000111110000000"];
    numbmp[7] = ["1111111111111","1111111111111","0000000001110","0000000011100","0000000111000","0000000110000","0000001100000","0000011100000","0000111000000","0000110000000","0001100000000","0011100000000","0011000000000","0111000000000","1110000000000","1100000000000","1100000000000"];
    numbmp[8] = ["0000000111110000","0000011111111100","0000011000001110","0000110000000111","0000110000011111","0000110001111000","0000011111100000","0000011110000000","0001111111000000","0011100011100000","0111000001110000","1110000000110000","1100000000110000","1100000001110000","1110000011100000","0111111111000000","0001111100000000"];
    numbmp[9] = ["0000011111000","0001111111110","0011100000110","0011000000011","0110000000011","0110000000011","0110000000011","0110000000111","0011000011110","0011111111110","0000111100110","0000000001100","0000000011000","0000000111000","0000011110000","1111111000000","1111110000000"];
    return numbmp;
}


function captchapng(width,height,dispNumber) {
    this.width   = width;
    this.height  = height;
    this.depth   = 8;
    this.dispNumber = ""+dispNumber.toString();
    this.widthAverage = parseInt(this.width/this.dispNumber.length);

    var p = new pnglib(this.width,this.height,this.depth);

    for (var numSection=0;numSection<this.dispNumber.length;numSection++){

        var dispNum = this.dispNumber[numSection].valueOf();

        var font = parseInt(Math.random()*myself.numMask.length);
        font = (font>=myself.numMask.length?0:font);
        //var random_x_offs = 0, random_y_offs = 0;
        var random_x_offs = parseInt(Math.random()*(this.widthAverage - myself.numMask[font][dispNum][0].length));
        var random_y_offs = parseInt(Math.random()*(this.height - myself.numMask[font][dispNum].length));
        random_x_offs = (random_x_offs<0?0:random_x_offs);
        random_y_offs = (random_y_offs<0?0:random_y_offs);

        for (var i=0;(i<myself.numMask[font][dispNum].length) && ((i+random_y_offs)<this.height);i++){
            var lineIndex = p.index(this.widthAverage * numSection + random_x_offs,i+random_y_offs);
            for (var j=0;j<myself.numMask[font][dispNum][i].length;j++){
                if ((myself.numMask[font][dispNum][i][j]=='1') && (this.widthAverage * numSection + random_x_offs+j)<this.width){
                    p.buffer[lineIndex+j]='\x01';
                }
            }
        }
    }
    return p;
}

function randomNumber(digits) {
    var number = "";
    for (var i = 0; i < digits; i++) {
        number += Math.floor(Math.random() * 10);
        if (number === '0') { number = ''; i--;}
    }
    return number;
}

const r = randomNumber(digits);

var p = new captchapng(80,30,parseInt(r)); // width,height,numeric captcha
        p.color(0, 0, 0, 0);  // First color: background (red, green, blue, alpha)
        p.color(80, 80, 80, 255); // Second color: paint (red, green, blue, alpha)

        var img = p.getBase64();

return {num: r, img:img};

$$
