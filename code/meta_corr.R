#### meta_corr.R
####
#### Meta-analysis of correlations between BCT accuracy and
#### (i) self-report mindfulness, (ii) psychological wellbeing, (iii) executive function.
####
#### Effects are Fisher-z transformed (back-transformed to r for reporting).
#### Most samples contribute several correlations, so the primary model is a
#### three-level random-effects model (effects nested in samples) fitted per
#### construct, with cluster-robust standard errors (clusters = samples).
#### Sensitivity: effects aggregated to one per sample x construct assuming
#### a within-sample correlation of RHO_WITHIN, then a standard RE model.
####
#### Reads data via load_data.R; writes CSVs and figures to results/.

suppressMessages({
  library(here)
  library(dplyr)
  library(metafor)
  library(ragg)
})
source(here("code", "load_data.R"))

## =========================================================================
## 1. Effect sizes
## =========================================================================
dat_es <- escalc(measure = "ZCOR", ri = r_signed, ni = n, data = as.data.frame(corr_included), var.names = c("yi", "vi"))
dat <- as_tibble(dat_es)
categories <- levels(dat$category)

## =========================================================================
## 2. Models
## =========================================================================
# I^2 for multilevel models (Cheung 2014; metafor-project.org/doku.php/tips:i2_multilevel_multivariate)
mv_i2 <- function(res) {
  W <- diag(1 / res$vi); X <- model.matrix(res)
  P <- W - W %*% X %*% solve(t(X) %*% W %*% X) %*% t(X) %*% W
  100 * sum(res$sigma2) / (sum(res$sigma2) + (res$k - res$p) / sum(diag(P)))
}

fit_3level <- function(d) {
  rma.mv(yi, vi, random = ~ 1 | sample_id / effect_id, data = d, method = "REML", slab = label)
}

summarise_3level <- function(res, name, rob = NULL) {
  pr <- predict(res, transf = transf.ztor)
  out <- tibble(model = name, k_effects = res$k, k_samples = res$s.nlevels[1],
                r = transf.ztor(res$b[1]), ci.lb = transf.ztor(res$ci.lb[1]), ci.ub = transf.ztor(res$ci.ub[1]),
                z = res$b[1], se_z = res$se[1], pval = res$pval[1], pi.lb = pr$pi.lb, pi.ub = pr$pi.ub,
                sigma2_sample = res$sigma2[1], sigma2_effect = res$sigma2[2], I2 = mv_i2(res),
                Q = res$QE, Q_df = res$k - res$p, Q_pval = res$QEp)
  if (!is.null(rob)) out <- out %>% mutate(robust_ci.lb = transf.ztor(rob$ci.lb[1]), robust_ci.ub = transf.ztor(rob$ci.ub[1]),
                                           robust_pval = rob$pval[1], robust_df = rob$dfs)
  out
}

fits <- lapply(categories, function(cat) {
  d <- dat %>% filter(category == cat)
  res <- fit_3level(d)
  rob <- robust(res, cluster = d$sample_id)   # cluster-robust (sandwich) inference; few clusters -> wide CIs
  list(res = res, rob = rob, d = d)
})
names(fits) <- categories

# all effects in one model with construct as moderator (test of differences between constructs)
res_all <- rma.mv(yi, vi, mods = ~ category - 1, random = ~ 1 | sample_id / effect_id, data = dat, method = "REML")
res_diff <- rma.mv(yi, vi, mods = ~ category, random = ~ 1 | sample_id / effect_id, data = dat, method = "REML")

## sensitivity: aggregate to one effect per sample x construct, then standard RE model
dat_es$cluster <- paste(dat_es$sample_id, dat_es$category)
dat_agg <- aggregate(dat_es, cluster = cluster, rho = RHO_WITHIN, select = c("sample_id", "label", "category", "yi", "vi"))
dat_agg <- as_tibble(dat_agg) %>% left_join(dat %>% count(sample_id, category, name = "n_effects"), by = c("sample_id", "category"))
fits_agg <- lapply(categories, function(cat) rma.uni(yi, vi, data = dat_agg, subset = category == cat, method = "REML", slab = label))
names(fits_agg) <- categories

egger <- regtest(rma.uni(yi, vi, data = dat_agg, method = "REML"), model = "rma", predictor = "sei")

## =========================================================================
## 3. Tables
## =========================================================================
models <- bind_rows(lapply(categories, function(cat) summarise_3level(fits[[cat]]$res, paste0(cat, " (3-level)"), fits[[cat]]$rob))) %>%
  bind_rows(lapply(categories, function(cat) {
    m <- fits_agg[[cat]]; pr <- predict(m, transf = transf.ztor)
    tibble(model = paste0(cat, " (aggregated, rho = ", RHO_WITHIN, ")"), k_effects = m$k, k_samples = m$k,
           r = transf.ztor(m$b[1]), ci.lb = transf.ztor(m$ci.lb), ci.ub = transf.ztor(m$ci.ub),
           z = m$b[1], se_z = m$se, pval = m$pval, pi.lb = pr$pi.lb, pi.ub = pr$pi.ub,
           I2 = m$I2, Q = m$QE, Q_df = m$k - 1, Q_pval = m$QEp)
  })) %>%
  bind_rows(tibble(model = "difference between constructs (3-level, QM test)", k_effects = res_diff$k,
                   Q = res_diff$QM, Q_df = res_diff$m, Q_pval = res_diff$QMp)) %>%
  bind_rows(tibble(model = "Egger regression test (aggregated effects, all constructs)", k_effects = egger$fit$k,
                   z = egger$zval, pval = egger$pval))

write.csv(dat %>% select(effect_id, sample_id, pub_id, label, study, category, correlate, n, r, reverse, r_signed, yi, vi, warnings),
          file.path(RESULTS_DIR, "corr_effects.csv"), row.names = FALSE)
write.csv(dat_agg %>% mutate(r = transf.ztor(yi)), file.path(RESULTS_DIR, "corr_effects_aggregated.csv"), row.names = FALSE)
write.csv(models, file.path(RESULTS_DIR, "corr_models.csv"), row.names = FALSE)

## =========================================================================
## 4. Forest plot (all effects, grouped by construct; polygons = 3-level models)
## =========================================================================
fmt <- function(x, d = 2) formatC(x, digits = d, format = "f")
pstr <- function(p) ifelse(p < .001, "p < .001", paste0("p = ", formatC(p, digits = 3, format = "f")))
pooled_label <- function(res, rob) {
  bquote(paste(bold("Pooled"), ": ", italic(r), " = ", .(fmt(transf.ztor(res$b[1]))),
               " [", .(fmt(transf.ztor(res$ci.lb))), ", ", .(fmt(transf.ztor(res$ci.ub))), "], ", .(pstr(res$pval)),
               "; robust CI [", .(fmt(transf.ztor(rob$ci.lb))), ", ", .(fmt(transf.ztor(rob$ci.ub))), "]"))
}

plot_corr_forest <- function() {
  ks <- sapply(categories, function(cat) fits[[cat]]$res$k)
  # blocks from the bottom: last category lowest
  rows <- list(); start <- 3
  for (cat in rev(categories)) { rows[[cat]] <- start:(start + ks[cat] - 1); start <- max(rows[[cat]]) + 5 }
  rows <- rows[categories]
  d <- bind_rows(lapply(categories, function(cat) fits[[cat]]$d))
  top <- max(unlist(rows)); xlim <- c(-2.6, 1.9); hdr <- c(-1.45, -0.75); cex <- 0.75
  par(mar = c(4, 1, 1, 1))
  forest(d$yi, d$vi, slab = d$label, rows = unlist(rows), transf = transf.ztor,
         ylim = c(-1.8, top + 4), xlim = xlim, alim = c(-0.5, 1), at = seq(-0.5, 1, 0.25), cex = cex,
         header = c("Sample", "r [95% CI]"), xlab = expression(paste("Pearson ", italic(r))),
         ilab = cbind(d$correlate, d$n), ilab.xpos = hdr, ilab.pos = 4, refline = 0, efac = c(0, 1))
  text(hdr, top + 3, c("Correlate", expression(italic(N))), pos = 4, font = 2, cex = cex)
  for (cat in categories) {
    text(xlim[1], max(rows[[cat]]) + 1.3, cat, pos = 4, font = 4, cex = cex * 1.15)
    addpoly(fits[[cat]]$res, row = min(rows[[cat]]) - 1.2, transf = transf.ztor,
            mlab = list(pooled_label(fits[[cat]]$res, fits[[cat]]$rob)), cex = cex, efac = 1.3)
  }
  text(xlim[1], -0.5, pos = 4, cex = cex * 0.9,
       bquote(paste("Signs flipped where needed so that positive ", italic(r), " = higher BCT accuracy with more mindfulness / better wellbeing / better EF.")))
  text(xlim[1], -1.3, pos = 4, cex = cex * 0.9, "Polygons: three-level random-effects models (effects nested in samples); robust CI = cluster-robust by sample.")
}

agg_png(file.path(RESULTS_DIR, "fig_corr_forest.png"), width = 7.5, height = 10.5, units = "in", res = 600, background = "white")
plot_corr_forest(); invisible(dev.off())
pdf(file.path(RESULTS_DIR, "fig_corr_forest.pdf"), width = 7.5, height = 10.5)
plot_corr_forest(); invisible(dev.off())

agg_png(file.path(RESULTS_DIR, "figS_corr_funnel.png"), width = 5, height = 5, units = "in", res = 300, background = "white")
funnel(rma.uni(yi, vi, data = dat_agg, method = "REML"), main = "Aggregated correlations (all constructs)", xlab = "Fisher z"); invisible(dev.off())

## =========================================================================
## 5. Console summary
## =========================================================================
cat("\n== Correlation meta-analysis (BCT) ==\n")
print(as.data.frame(models %>% select(model, k_effects, k_samples, r, ci.lb, ci.ub, pval, robust_ci.lb, robust_ci.ub, I2, Q_pval) %>%
                      mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
