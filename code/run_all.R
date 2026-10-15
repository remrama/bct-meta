#### run_all.R -- regenerate every result and figure from the raw extraction sheets.
####
####   Rscript code/run_all.R        (from the repository root; paths resolve via here::here())
####
#### Outputs land in results/. Nothing in data/ is modified.

## install anything missing, then load
pkgs <- c("here", "dplyr", "tidyr", "readxl", "metafor", "ragg")
missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
if (length(missing)) install.packages(missing)
suppressMessages(library(here))
t0 <- Sys.time()

for (script in c("load_data.R", "meta_prepost.R", "meta_corr.R")) {
  cat("\n######## ", script, " ########\n", sep = "")
  source(here("code", script), local = new.env())
}

## record the software environment next to the results
si <- sessionInfo()
writeLines(c(capture.output(print(si)), "", paste("Run completed:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))),
           here("results", "session_info.txt"))
cat(sprintf("\nDone in %.1f s. Session info written to results/session_info.txt\n", as.numeric(Sys.time() - t0, units = "secs")))
