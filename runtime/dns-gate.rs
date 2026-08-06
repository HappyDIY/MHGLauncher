#![no_std]
#![crate_type = "cdylib"]

use core::ffi::{c_char, c_int, c_void};
use core::panic::PanicInfo;
use core::ptr;

const AF_INET: c_int = 2;
const AF_INET6: c_int = 30;
const EAI_NONAME: c_int = 8;
const EPERM: c_int = 1;
const HOST_NOT_FOUND: c_int = 1;
const NI_MAXHOST: usize = 1025;
const NI_NUMERICHOST: c_int = 2;
const NS_T_A: c_int = 1;
const NS_T_AAAA: c_int = 28;
const O_APPEND: c_int = 0x0008;
const O_CREAT: c_int = 0x0200;
const O_WRONLY: c_int = 0x0001;

#[repr(C)]
struct SockAddr {
    _private: [u8; 0],
}

#[repr(C)]
struct AddrInfo {
    ai_flags: c_int,
    ai_family: c_int,
    ai_socktype: c_int,
    ai_protocol: c_int,
    ai_addrlen: u32,
    ai_canonname: *mut c_char,
    ai_addr: *mut SockAddr,
    ai_next: *mut AddrInfo,
}

#[repr(C)]
struct HostEnt {
    h_name: *mut c_char,
    h_aliases: *mut *mut c_char,
    h_addrtype: c_int,
    h_length: c_int,
    h_addr_list: *mut *mut c_char,
}

#[repr(C)]
struct TimeVal {
    tv_sec: i64,
    tv_usec: i32,
}

#[repr(C)]
struct Interpose {
    replacement: *const (),
    replacee: *const (),
}

unsafe impl Sync for Interpose {}

#[link(name = "System")]
unsafe extern "C" {
    static mut h_errno: c_int;

    fn __error() -> *mut c_int;
    fn access(path: *const c_char, mode: c_int) -> c_int;
    fn close(descriptor: c_int) -> c_int;
    fn getenv(name: *const c_char) -> *mut c_char;
    fn getaddrinfo(
        name: *const c_char,
        service: *const c_char,
        hints: *const AddrInfo,
        result: *mut *mut AddrInfo,
    ) -> c_int;
    fn gethostbyname(name: *const c_char) -> *mut HostEnt;
    fn gethostbyname2(name: *const c_char, family: c_int) -> *mut HostEnt;
    fn getnameinfo(
        address: *const SockAddr,
        address_length: u32,
        host: *mut c_char,
        host_length: u32,
        service: *mut c_char,
        service_length: u32,
        flags: c_int,
    ) -> c_int;
    fn getpid() -> c_int;
    fn gettimeofday(time: *mut TimeVal, zone: *mut c_void) -> c_int;
    fn inet_ntop(
        family: c_int,
        address: *const c_void,
        output: *mut c_char,
        length: u32,
    ) -> *const c_char;
    fn kill(pid: c_int, signal: c_int) -> c_int;
    fn open(path: *const c_char, flags: c_int, mode: c_int) -> c_int;
    fn unlink(path: *const c_char) -> c_int;
    fn write(descriptor: c_int, buffer: *const c_void, length: usize) -> isize;
}

#[link(name = "resolv")]
unsafe extern "C" {
    #[link_name = "res_9_query"]
    fn res_query(
        name: *const c_char,
        dns_class: c_int,
        query_type: c_int,
        answer: *mut u8,
        length: c_int,
    ) -> c_int;
}

#[panic_handler]
fn panic(_: &PanicInfo<'_>) -> ! {
    loop {}
}

unsafe fn environment(name: &[u8]) -> *const c_char {
    unsafe { getenv(name.as_ptr().cast()) }
}

unsafe fn parse_owner_pid(value: *const c_char) -> Option<c_int> {
    if value.is_null() {
        return None;
    }
    let mut cursor = value.cast::<u8>();
    let mut pid: c_int = 0;
    let mut digits = 0;
    while unsafe { *cursor } != 0 {
        let digit = unsafe { *cursor };
        if !digit.is_ascii_digit() {
            return None;
        }
        pid = pid
            .checked_mul(10)?
            .checked_add(c_int::from(digit - b'0'))?;
        digits += 1;
        cursor = unsafe { cursor.add(1) };
    }
    (digits > 0 && pid > 1).then_some(pid)
}

unsafe fn gate_active() -> bool {
    let path = unsafe { environment(b"MHG_DNS_GATE_FILE\0") };
    let owner = unsafe { environment(b"MHG_DNS_GATE_OWNER_PID\0") };
    if path.is_null() || unsafe { access(path, 0) } != 0 {
        return false;
    }
    let Some(pid) = (unsafe { parse_owner_pid(owner) }) else {
        return false;
    };
    unsafe { kill(pid, 0) == 0 || *__error() == EPERM }
}

unsafe fn equals_ignore_ascii_case(mut left: *const c_char, right: &[u8]) -> bool {
    for expected in right {
        let actual = unsafe { *left.cast::<u8>() };
        if actual.to_ascii_lowercase() != *expected {
            return false;
        }
        left = unsafe { left.add(1) };
    }
    unsafe { *left == 0 }
}

unsafe fn blocked(name: *const c_char) -> bool {
    if name.is_null() || !unsafe { gate_active() } {
        return false;
    }
    let matches = unsafe {
        equals_ignore_ascii_case(name, b"dispatchcnglobal.yuanshen.com")
            || equals_ignore_ascii_case(name, b"dispatchosglobal.yuanshen.com")
    };
    if matches {
        let path = unsafe { environment(b"MHG_DNS_GATE_FILE\0") };
        if !path.is_null() {
            unsafe { unlink(path) };
        }
    }
    matches
}

struct LineBuffer {
    bytes: [u8; 768],
    length: usize,
}

impl LineBuffer {
    const fn new() -> Self {
        Self {
            bytes: [0; 768],
            length: 0,
        }
    }

    fn push(&mut self, byte: u8) {
        if self.length < self.bytes.len() {
            self.bytes[self.length] = byte;
            self.length += 1;
        }
    }

    fn push_bytes(&mut self, bytes: &[u8]) {
        for byte in bytes {
            self.push(*byte);
        }
    }

    fn push_integer(&mut self, value: i64) {
        let mut digits = [0_u8; 20];
        let negative = value < 0;
        let mut magnitude = value.unsigned_abs();
        let mut count = 0;
        loop {
            digits[count] = (magnitude % 10) as u8 + b'0';
            count += 1;
            magnitude /= 10;
            if magnitude == 0 {
                break;
            }
        }
        if negative {
            self.push(b'-');
        }
        while count > 0 {
            count -= 1;
            self.push(digits[count]);
        }
    }

    unsafe fn push_host(&mut self, host: *const c_char) {
        let mut cursor = host.cast::<u8>();
        for _ in 0..511 {
            let byte = unsafe { *cursor };
            if byte == 0 {
                break;
            }
            self.push(if matches!(byte, b'\t' | b'\n' | b'\r') {
                b'?'
            } else {
                byte
            });
            cursor = unsafe { cursor.add(1) };
        }
    }

    unsafe fn push_c_string(&mut self, value: *const c_char) {
        if value.is_null() {
            return;
        }
        let mut cursor = value.cast::<u8>();
        while unsafe { *cursor } != 0 {
            self.push(unsafe { *cursor });
            cursor = unsafe { cursor.add(1) };
        }
    }
}

unsafe fn log_query(
    api: &[u8],
    name: *const c_char,
    denied: bool,
    result: c_int,
    address: *const c_char,
) {
    let path = unsafe { environment(b"MHG_DNS_LOG_FILE\0") };
    if path.is_null() || name.is_null() {
        return;
    }
    let mut time = TimeVal {
        tv_sec: 0,
        tv_usec: 0,
    };
    unsafe { gettimeofday(&mut time, ptr::null_mut()) };

    let mut line = LineBuffer::new();
    line.push_integer(time.tv_sec * 1000 + i64::from(time.tv_usec) / 1000);
    line.push(b'\t');
    line.push_integer(i64::from(unsafe { getpid() }));
    line.push(b'\t');
    line.push_bytes(api);
    line.push(b'\t');
    unsafe { line.push_host(name) };
    line.push(b'\t');
    line.push_bytes(if denied { b"blocked" } else { b"allowed" });
    line.push(b'\t');
    line.push_integer(i64::from(result));
    line.push(b'\t');
    unsafe { line.push_c_string(address) };
    line.push(b'\n');

    let descriptor = unsafe { open(path, O_WRONLY | O_APPEND | O_CREAT, 0o600) };
    if descriptor < 0 {
        return;
    }
    unsafe {
        write(descriptor, line.bytes.as_ptr().cast(), line.length);
        close(descriptor);
    }
}

unsafe extern "C" fn mhg_getaddrinfo(
    name: *const c_char,
    service: *const c_char,
    hints: *const AddrInfo,
    result: *mut *mut AddrInfo,
) -> c_int {
    let api = if !hints.is_null() && unsafe { (*hints).ai_family } == AF_INET6 {
        b"getaddrinfo/AAAA".as_slice()
    } else if !hints.is_null() && unsafe { (*hints).ai_family } == AF_INET {
        b"getaddrinfo/A".as_slice()
    } else {
        b"getaddrinfo/ANY".as_slice()
    };
    if unsafe { blocked(name) } {
        unsafe { log_query(api, name, true, EAI_NONAME, ptr::null()) };
        return EAI_NONAME;
    }
    let code = unsafe { getaddrinfo(name, service, hints, result) };
    let mut address = [0 as c_char; NI_MAXHOST];
    if code == 0 && !result.is_null() && !unsafe { *result }.is_null() {
        let resolved = unsafe { &**result };
        unsafe {
            getnameinfo(
                resolved.ai_addr,
                resolved.ai_addrlen,
                address.as_mut_ptr(),
                address.len() as u32,
                ptr::null_mut(),
                0,
                NI_NUMERICHOST,
            );
        }
    }
    unsafe { log_query(api, name, false, code, address.as_ptr()) };
    code
}

unsafe fn host_address(result: *mut HostEnt, address: &mut [c_char; 46]) {
    if result.is_null() {
        return;
    }
    let list = unsafe { (*result).h_addr_list };
    if list.is_null() || unsafe { *list }.is_null() {
        return;
    }
    unsafe {
        inet_ntop(
            (*result).h_addrtype,
            (*list).cast(),
            address.as_mut_ptr(),
            address.len() as u32,
        );
    }
}

unsafe extern "C" fn mhg_gethostbyname(name: *const c_char) -> *mut HostEnt {
    if unsafe { blocked(name) } {
        unsafe {
            h_errno = HOST_NOT_FOUND;
            log_query(b"gethostbyname", name, true, h_errno, ptr::null());
        }
        return ptr::null_mut();
    }
    let result = unsafe { gethostbyname(name) };
    let mut address = [0 as c_char; 46];
    unsafe { host_address(result, &mut address) };
    let code = if result.is_null() {
        unsafe { h_errno }
    } else {
        0
    };
    unsafe { log_query(b"gethostbyname", name, false, code, address.as_ptr()) };
    result
}

unsafe extern "C" fn mhg_gethostbyname2(name: *const c_char, family: c_int) -> *mut HostEnt {
    if unsafe { blocked(name) } {
        unsafe {
            h_errno = HOST_NOT_FOUND;
            log_query(b"gethostbyname2", name, true, h_errno, ptr::null());
        }
        return ptr::null_mut();
    }
    let result = unsafe { gethostbyname2(name, family) };
    let mut address = [0 as c_char; 46];
    unsafe { host_address(result, &mut address) };
    let code = if result.is_null() {
        unsafe { h_errno }
    } else {
        0
    };
    unsafe { log_query(b"gethostbyname2", name, false, code, address.as_ptr()) };
    result
}

unsafe extern "C" fn mhg_res_query(
    name: *const c_char,
    dns_class: c_int,
    query_type: c_int,
    answer: *mut u8,
    length: c_int,
) -> c_int {
    if unsafe { blocked(name) } {
        unsafe {
            h_errno = HOST_NOT_FOUND;
            log_query(b"res_query", name, true, h_errno, ptr::null());
        }
        return -1;
    }
    let result = unsafe { res_query(name, dns_class, query_type, answer, length) };
    let api = match query_type {
        NS_T_AAAA => b"res_query/AAAA".as_slice(),
        NS_T_A => b"res_query/A".as_slice(),
        _ => b"res_query".as_slice(),
    };
    let code = if result < 0 { unsafe { h_errno } } else { 0 };
    unsafe { log_query(api, name, false, code, ptr::null()) };
    result
}

#[used]
#[link_section = "__DATA,__interpose"]
static GETADDRINFO_INTERPOSE: Interpose = Interpose {
    replacement: mhg_getaddrinfo as *const (),
    replacee: getaddrinfo as *const (),
};

#[used]
#[link_section = "__DATA,__interpose"]
static GETHOSTBYNAME_INTERPOSE: Interpose = Interpose {
    replacement: mhg_gethostbyname as *const (),
    replacee: gethostbyname as *const (),
};

#[used]
#[link_section = "__DATA,__interpose"]
static GETHOSTBYNAME2_INTERPOSE: Interpose = Interpose {
    replacement: mhg_gethostbyname2 as *const (),
    replacee: gethostbyname2 as *const (),
};

#[used]
#[link_section = "__DATA,__interpose"]
static RES_QUERY_INTERPOSE: Interpose = Interpose {
    replacement: mhg_res_query as *const (),
    replacee: res_query as *const (),
};
