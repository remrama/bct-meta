#### run_all.R -- regenerate every result and figure from the raw extraction sheets.
####
####   Rscript code/run_all.R        (from the repository root, so .Rprofile activates renv)
####
#### Package versions are pinned in renv.lock; install them once with
####   Rscript -e "renv::restore()"
####
#### Outputs land in derivatives/. Nothing in sourcedata/ is modified.

## refuse to run against whatever happens to be in the user library
if (!nzchar(Sys.getenv("RENV_PROJECT")))
  stop("renv is not active. Run from the repository root: Rscript code/run_all.R", call. = FALSE)
pkgs <- c("here", "dplyr", "tidyr", "readxl", "metafor", "ragg")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing))
  stop("Missing packages: ", paste(missing, collapse = ", "), '. Run Rscript -e "renv::restore()" first.', call. = FALSE)
suppressMessages(library(here))
t0 <- Sys.time()

for (script in c("load_data.R", "meta_prepost.R", "meta_corr.R")) {
  cat("\n######## ", script, " ########\n", sep = "")
  source(here("code", script), local = new.env())
}

## record the software environment next to the results
si <- sessionInfo()
writeLines(c(capture.output(print(si)), "", paste("Run completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))),
           here("derivatives", "session_info.txt"))
cat(sprintf("\nDone in %.1f s. Session info written to derivatives/session_info.txt\n", as.numeric(Sys.time() - t0, units = "secs")))
