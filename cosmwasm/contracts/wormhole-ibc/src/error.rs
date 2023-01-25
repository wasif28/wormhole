use thiserror::Error;

#[derive(Error, Debug)]
pub enum ContractError {
    #[error("non governance vaa")]
    InvalidVAAType,
    #[error("non wormchain emitter registration")]
    InvalidChainRegistration
}

// Workaround for not being able to use the `bail!` macro directly.
#[doc(hidden)]
#[macro_export]
macro_rules! bail {
    ($msg:literal $(,)?) => {
        return ::core::result::Result::Err(::anyhow::anyhow!($msg).into())
    };
    ($err:expr $(,)?) => {
        return ::core::result::Result::Err(::anyhow::anyhow!($err).into())
    };
    ($fmt:expr, $($arg:tt)*) => {
        return ::core::result::Result::Err(::anyhow::anyhow!($fmt, $($arg)*).into())
    };
}