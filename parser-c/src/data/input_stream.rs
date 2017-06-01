mod haskell_support {
    pub trait Addable {
        fn add(self, right: Self) -> Self;
    }

    impl Addable for String {
        fn add(self, right: Self) -> Self {
            format!("{}{}", self, right)
        }
    }

    pub fn __op_addadd<A: Addable>(left: A, right: A) -> A {
        Addable::add(left, right)
    }
}


pub mod Language_C_Data_InputStream {
    use haskell_support::*;

use Data::Word;
use Data::ByteString;
use ByteString;
use Data::ByteString;
use Data::ByteString::Char8;
use Data::Char;

    pub fn countLines() -> isize {
        match () {
            () => {
                length(BSC::lines)
            },
            () => {
                length(lines)
            },
        }
    }

    pub fn inputStreamEmpty() -> bool {
        match () {
            () => {
                BSW::null
            },
            () => {
                null
            },
        }
    }

    pub fn inputStreamFromString() -> InputStream {
        match () {
            () => {
                BSC::pack
            },
            () => {
                id
            },
        }
    }

    pub fn inputStreamToString() -> String {
        match () {
            () => {
                BSC::unpack
            },
            () => {
                id
            },
        }
    }

    pub fn readInputStream() -> IO<InputStream> {
        match () {
            () => {
                BSW::readFile
            },
            () => {
                readFile
            },
        }
    }

    pub fn takeByte(__0: InputStream) -> (Word8, InputStream) {
        match (__0) {
            bs => {
                seq(BSW::head(bs), (BSW::head(bs), BSW::tail(bs)))
            },
            bs => {
                /* Expr::Error */ Error
            },
        }
    }

    pub fn takeChar(__0: InputStream) -> (Char, InputStream) {
        match (__0) {
            bs => {
                seq(BSC::head(bs), (BSC::head(bs), BSC::tail(bs)))
            },
            bs => {
                (head(bs), tail(bs))
            },
        }
    }

    pub fn takeChars(__0: isize, __1: InputStream) -> Vec<Char> {
        match (__0, __1) {
            (n, bstr) => {
                BSC::unpack(BSC::take(n, bstr))
            },
            (n, __str) => {
                take(n, __str)
            },
        }
    }

}




