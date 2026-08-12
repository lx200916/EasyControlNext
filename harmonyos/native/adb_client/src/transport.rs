//! Transport abstraction for ADB bytes. Production uses TCP; tests use TcpStream to a fake daemon.

use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::time::Duration;

use crate::error::{AdbError, AdbResult};

/// Byte-oriented ADB transport. Keep this sync so host unit/integration tests stay simple.
pub trait AdbTransport {
  fn read_exact(&mut self, buf: &mut [u8]) -> AdbResult<()>;
  fn write_all(&mut self, buf: &[u8]) -> AdbResult<()>;
  fn set_read_timeout(&mut self, timeout: Option<Duration>) -> AdbResult<()>;
  fn set_write_timeout(&mut self, timeout: Option<Duration>) -> AdbResult<()>;
  fn close(&mut self) -> AdbResult<()>;
}

impl AdbTransport for TcpStream {
  fn read_exact(&mut self, buf: &mut [u8]) -> AdbResult<()> {
    Read::read_exact(self, buf).map_err(AdbError::from)
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
