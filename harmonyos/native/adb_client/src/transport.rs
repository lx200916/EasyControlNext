//! Transport abstraction for ADB bytes. Production uses TCP / TLS; tests use TcpStream to a fake daemon.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

use rustls::{ClientConnection, StreamOwned};

use crate::error::{AdbError, AdbResult};

/// Byte-oriented ADB transport. Keep this sync so host unit/integration tests stay simple.
pub trait AdbTransport {
  /// Partial read (may return 0..=buf.len()). Used to survive read timeouts mid-message.
  fn read_some(&mut self, buf: &mut [u8]) -> AdbResult<usize>;
  /// Fill `buf` completely. If a read timeout hits after a partial fill, keep waiting —
  /// never return Timeout with bytes already consumed from the socket (that desyncs ADB).
  fn read_exact(&mut self, buf: &mut [u8]) -> AdbResult<()> {
    let mut off = 0usize;
    while off < buf.len() {
      match self.read_some(&mut buf[off..]) {
        Ok(0) => {
          return Err(AdbError::Io(std::io::Error::new(
            std::io::ErrorKind::UnexpectedEof,
            "adb transport EOF",
          )));
        }
        Ok(n) => off += n,
        // No progress yet — surface idle timeout to callers (pump / wait loops).
        Err(AdbError::Timeout) if off == 0 => return Err(AdbError::Timeout),
        // Partial message already in `buf` — continue; dropping would desync the stream.
        Err(AdbError::Timeout) => continue,
        Err(e) => return Err(e),
      }
    }
    Ok(())
  }
  fn write_all(&mut self, buf: &[u8]) -> AdbResult<()>;
  fn set_read_timeout(&mut self, timeout: Option<Duration>) -> AdbResult<()>;
  fn set_write_timeout(&mut self, timeout: Option<Duration>) -> AdbResult<()>;
  fn close(&mut self) -> AdbResult<()>;
}

impl AdbTransport for TcpStream {
  fn read_some(&mut self, buf: &mut [u8]) -> AdbResult<usize> {
    Read::read(self, buf).map_err(AdbError::from)
  }

  fn write_all(&mut self, buf: &[u8]) -> AdbResult<()> {
    Write::write_all(self, buf).map_err(AdbError::from)?;
    self.flush().map_err(AdbError::from)
  }

  fn set_read_timeout(&mut self, timeout: Option<Duration>) -> AdbResult<()> {
    TcpStream::set_read_timeout(self, timeout).map_err(AdbError::from)
  }

  fn set_write_timeout(&mut self, timeout: Option<Duration>) -> AdbResult<()> {
    TcpStream::set_write_timeout(self, timeout).map_err(AdbError::from)
  }

  fn close(&mut self) -> AdbResult<()> {
    let _ = self.shutdown(std::net::Shutdown::Both);
    Ok(())
  }
}

/// Production session I/O: plaintext TCP (USB/classic 5555) or TLS after A_STLS.
pub enum SessionIo {
  Plain(TcpStream),
  Tls(Box<StreamOwned<ClientConnection, TcpStream>>),
}

impl AdbTransport for SessionIo {
  fn read_some(&mut self, buf: &mut [u8]) -> AdbResult<usize> {
    match self {
      Self::Plain(s) => Read::read(s, buf).map_err(AdbError::from),
      Self::Tls(s) => Read::read(s.as_mut(), buf).map_err(AdbError::from),
    }
  }

  fn write_all(&mut self, buf: &[u8]) -> AdbResult<()> {
    match self {
      Self::Plain(s) => {
        Write::write_all(s, buf).map_err(AdbError::from)?;
        s.flush().map_err(AdbError::from)
      }
      Self::Tls(s) => {
        Write::write_all(s.as_mut(), buf).map_err(AdbError::from)?;
        s.flush().map_err(AdbError::from)
      }
    }
  }

  fn set_read_timeout(&mut self, timeout: Option<Duration>) -> AdbResult<()> {
    match self {
      Self::Plain(s) => TcpStream::set_read_timeout(s, timeout).map_err(AdbError::from),
      Self::Tls(s) => TcpStream::set_read_timeout(&s.sock, timeout).map_err(AdbError::from),
    }
  }

  fn set_write_timeout(&mut self, timeout: Option<Duration>) -> AdbResult<()> {
    match self {
      Self::Plain(s) => TcpStream::set_write_timeout(s, timeout).map_err(AdbError::from),
      Self::Tls(s) => TcpStream::set_write_timeout(&s.sock, timeout).map_err(AdbError::from),
    }
  }

  fn close(&mut self) -> AdbResult<()> {
    match self {
      Self::Plain(s) => {
        let _ = s.shutdown(std::net::Shutdown::Both);
      }
      Self::Tls(s) => {
        let _ = s.sock.shutdown(std::net::Shutdown::Both);
      }
    }
    Ok(())
  }
}

/// Connect to `host:port` with connect + IO timeouts.
pub fn connect_tcp(host: &str, port: u16, timeout: Duration) -> AdbResult<TcpStream> {
  let addr = format!("{host}:{port}");
  let mut addrs = addr.to_socket_addrs().map_err(AdbError::from)?;
  let sock = addrs.next().ok_or_else(|| {
    AdbError::Io(std::io::Error::new(
      std::io::ErrorKind::InvalidInput,
      "empty address list",
    ))
  })?;
  let stream = TcpStream::connect_timeout(&sock, timeout)?;
  stream.set_nodelay(true)?;
  stream.set_read_timeout(Some(timeout))?;
  stream.set_write_timeout(Some(timeout))?;
  Ok(stream)
}
