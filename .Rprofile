options(
  repos = c(
    # Default CRAN repository
    CRAN = "https://packagemanager.rstudio.com/cran/__linux__/jammy/latest",
    # RStudio Package Manager repository
    RSPM = "https://packagemanager.rstudio.com/cran/__linux__/jammy/latest"
  )
)

# Set a custom root path for renv
Sys.setenv(RENV_PATHS_ROOT = "/usrfiles/renv_cache/")

# Set the cache path for renv
Sys.setenv(RENV_PATHS_CACHE = "/usrfiles/renv_cache/cache")

# Set a custom local repository path for renv
Sys.setenv(RENV_PATHS_LOCAL = "/usrfiles/renv_cache/local/repository")

# Set a custom source path for renv
Sys.setenv(RENV_PATHS_SOURCE = "/usrfiles/renv_cache/source")

# Set a custom binary path for renv
# Sys.setenv(RENV_PATHS_BINARY = file.path(tempdir(), "binary"))
Sys.setenv(RENV_PATHS_BINARY = "/usrfiles/renv_cache/binary")

# Disable the renv sandbox to allow for more flexible operations
Sys.setenv(RENV_CONFIG_SANDBOX_ENABLED = "FALSE")

# Set the path for the tar tool used in building R packages
Sys.setenv(R_BUILD_TAR = "/usr/bin/tar")

# Print a message indicating that renv setup has been initialized from .Rprofile
print("renv setup initialized from .Rprofile")

# Activate the renv environment using the specified script
source("renv/activate.R")