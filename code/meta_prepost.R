#### meta_prepost.R
####
#### Meta-analysis of BCT accuracy before vs after an intervention.
####
#### Three quantities, all in pre-test SD units (Hedges-corrected):
####   (a) within-arm standardized mean change for intervention arms     (SMCR)
####   (b) within-arm standardized mean change for control arms          (SMCR)
####   (c) controlled effect = (a) - (b) within each study               (Becker 1988)
#### (c) is the headline estimate; (a)/(b) show that the task moves with
#### training and is stable without it.
####
#### Pre/post correlation is not reported by any study, so r = R_PREPOST is
#### assumed (Morris & DeShon 2002) with sensitivity analyses over R_PREPOST_SENS.
####
#### Reads data via load_data.R; writes CSVs and figures to derivatives/.

suppressMessages({
  library(here)
  library(dplyr)
  library(tidyr)
  library(metafor)
  library(ragg)
})
source(here("code", "load_data.R"))

## =========================================================================
## 1. Pool multiple control arms within a study (Levinson 2014: n-back + no training)
## =========================================================================
pool_arms <- function(d) {
  # combine arms into one group: weighted mean, SD from the combined-group formula
  n  <- sum(d$n)
  m1 <- sum(d$n * d$mean1) / n
  m2 <- sum(d$n * d$mean2) / n
  pooled_sd <- function(ni, mi, sdi, m) sqrt((sum((ni - 1) * sdi^2) + sum(ni * (mi - m)^2)) / (n - 1))
  tibble(n = n, mean1 = m1, sd1 = pooled_sd(d$n, d$mean1, d$sd1, m1),
         mean2 = m2, sd2 = pooled_sd(d$n, d$mean2, d$sd2, m2),
         arm_label = paste(sub("no training", "none", d$arm_label), collapse = " + "),   # pooled arms joined with "+"
         extraction_source = paste(unique(d$extraction_source), collapse = "; "),
         n_arms_pooled = nrow(d))
}

arms <- prepost_included %>%
  group_by(pub_id, label, author, year, arm, intervention_length) %>%
  group_modify(~ pool_arms(.x)) %>%
  ungroup() %>%
  arrange(desc(arm), year, author)

## =========================================================================
## 2. Effect sizes
## =========================================================================
smcr <- function(d, ri) {
  # standardized mean change, raw-score (pre-test SD) standardization, Hedges-corrected
  escalc(measure = "SMCR", m1i = mean2, m2i = mean1, sd1i = sd1, ni = n, ri = rep(ri, nrow(d)),
         data = d, var.names = c("yi", "vi"))
}

controlled_effects <- function(arms, ri) {
  a <- as_tibble(smcr(arms, ri))
  wide <- a %>%
    select(pub_id, label, author, year, arm, n, yi, vi, arm_label) %>%
    pivot_wider(names_from = arm, values_from = c(n, yi, vi, arm_label))
  wide %>%
    mutate(yi = yi_intervention - yi_control,       # Becker (1988): difference of independent SMCs
           vi = vi_intervention + vi_control,
           ri = ri) %>%
    arrange(year, author)
}

arms_es <- as_tibble(smcr(arms, R_PREPOST)) %>% mutate(ri = R_PREPOST)
ctrl_es <- controlled_effects(arms, R_PREPOST)

## =========================================================================
## 3. Models (REML random effects)
## =========================================================================
res_int  <- rma.uni(yi, vi, data = arms_es, subset = arm == "intervention", method = "REML", slab = label)
res_ctl  <- rma.uni(yi, vi, data = arms_es, subset = arm == "control",      method = "REML", slab = label)
res_arm  <- rma.uni(yi, vi, mods = ~ arm, data = arms_es, method = "REML")   # test: intervention vs control change
res_ctrl <- rma.uni(yi, vi, data = ctrl_es, method = "REML", slab = label)   # headline: controlled effect

## sensitivity: assumed pre/post correlation
sens <- bind_rows(lapply(c(R_PREPOST, R_PREPOST_SENS), function(r) {
  m <- rma.uni(yi, vi, data = controlled_effects(arms, r), method = "REML")
  tibble(r_prepost = r, k = m$k, estimate = m$b[1], ci.lb = m$ci.lb, ci.ub = m$ci.ub,
         pval = m$pval, tau2 = m$tau2, I2 = m$I2)
})) %>% arrange(r_prepost)

## leave-one-out on the headline model
l1o <- as_tibble(as.data.frame(leave1out(res_ctrl))) %>%
  mutate(omitted = ctrl_es$label, .before = 1)

## small-study effects (k is small; report, don't over-interpret)
egger <- regtest(res_ctrl, model = "rma", predictor = "sei")

## =========================================================================
## 4. Tables
## =========================================================================
summarise_model <- function(m, name) {
  pr <- predict(m)
  tibble(model = name, k = m$k, estimate = m$b[1], se = m$se[1], ci.lb = m$ci.lb[1], ci.ub = m$ci.ub[1],
         zval = m$zval[1], pval = m$pval[1], pi.lb = pr$pi.lb, pi.ub = pr$pi.ub,
         tau2 = m$tau2, I2 = m$I2, Q = m$QE, Q_df = m$k - m$p, Q_pval = m$QEp)
}
models <- bind_rows(
  summarise_model(res_int,  "intervention arms: standardized change"),
  summarise_model(res_ctl,  "control arms: standardized change"),
  summarise_model(res_ctrl, "controlled effect (intervention - control)")
) %>%
  bind_rows(tibble(model = "intervention vs control arms (moderator test)", k = res_arm$k,
                   estimate = res_arm$b[2], se = res_arm$se[2], ci.lb = res_arm$ci.lb[2], ci.ub = res_arm$ci.ub[2],
                   zval = res_arm$zval[2], pval = res_arm$pval[2], tau2 = res_arm$tau2, I2 = res_arm$I2,
                   Q = res_arm$QM, Q_df = res_arm$m, Q_pval = res_arm$QMp)) %>%
  bind_rows(tibble(model = "Egger regression test (controlled effect)", k = res_ctrl$k,
                   estimate = egger$est, zval = egger$zval, pval = egger$pval))

write.csv(arms_es %>% select(pub_id, label, arm, arm_label, n, mean1, sd1, mean2, sd2, ri, yi, vi, extraction_source, n_arms_pooled),
          file.path(DERIV_DIR, "prepost_effects_arms.csv"), row.names = FALSE)
write.csv(ctrl_es %>% select(pub_id, label, n_intervention, n_control, arm_label_intervention, arm_label_control, ri, yi, vi),
          file.path(DERIV_DIR, "prepost_effects_controlled.csv"), row.names = FALSE)
write.csv(models, file.path(DERIV_DIR, "prepost_models.csv"), row.names = FALSE)
write.csv(sens,   file.path(DERIV_DIR, "prepost_sensitivity_r.csv"), row.names = FALSE)
write.csv(l1o,    file.path(DERIV_DIR, "prepost_leave1out.csv"), row.names = FALSE)

## =========================================================================
## 5. Forest plot
## =========================================================================
fmt <- function(x, d = 2) formatC(x, digits = d, format = "f")
pstr <- function(p) ifelse(p < .001, "p < .001", paste0("p = ", formatC(p, digits = 3, format = "f")))
pooled_label <- function(m, name) {
  bquote(paste(bold(.(name)), ": ", .(fmt(m$b[1])), " [", .(fmt(m$ci.lb)), ", ", .(fmt(m$ci.ub)), "], ",
               .(pstr(m$pval)), "; ", I^2, " = ", .(fmt(m$I2, 0)), "%"))
}

plot_prepost_forest <- function() {
  k_int <- res_int$k; k_ctl <- res_ctl$k; k_ctr <- res_ctrl$k
  # rows from bottom: controlled effects, control arms, intervention arms (each block: rows + pooled + gap)
  rows_ctr <- 3:(2 + k_ctr)
  rows_ctl <- (max(rows_ctr) + 5):(max(rows_ctr) + 4 + k_ctl)
  rows_int <- (max(rows_ctl) + 5):(max(rows_ctl) + 4 + k_int)
  all_yi <- c(arms_es$yi[arms_es$arm == "intervention"], arms_es$yi[arms_es$arm == "control"], ctrl_es$yi)
  all_vi <- c(arms_es$vi[arms_es$arm == "intervention"], arms_es$vi[arms_es$arm == "control"], ctrl_es$vi)
  all_lab <- c(arms_es$label[arms_es$arm == "intervention"], arms_es$label[arms_es$arm == "control"], ctrl_es$label)
  all_ilab <- cbind(c(arms_es$arm_label[arms_es$arm == "intervention"], arms_es$arm_label[arms_es$arm == "control"],
                      paste(ctrl_es$arm_label_intervention, "vs", ctrl_es$arm_label_control)),
                    c(arms_es$n[arms_es$arm == "intervention"], arms_es$n[arms_es$arm == "control"],
                      paste0(ctrl_es$n_intervention, " / ", ctrl_es$n_control)))
  xlim <- c(-10, 5); hdr <- c(-6.1, -2.4); cex <- 0.8; top <- max(rows_int)
  par(mar = c(4, 1, 1, 1))
  forest(all_yi, all_vi, slab = all_lab, rows = c(rows_int, rows_ctl, rows_ctr),
         ylim = c(-1, top + 4), xlim = xlim, alim = c(-1, 2), at = seq(-1, 2, 0.5), cex = cex,
         header = c("Study", "g [95% CI]"), xlab = "Hedges' g (pre-test SD units)",
         ilab = all_ilab, ilab.xpos = hdr, ilab.pos = 4, refline = 0, efac = c(0, 1))
  text(hdr, top + 3, c("Condition", expression(italic(N))), pos = 4, font = 2, cex = cex)
  text(xlim[1], top + 1.3,           "Intervention arms: post - pre", pos = 4, font = 4, cex = cex * 1.1)
  text(xlim[1], max(rows_ctl) + 1.3, "Control arms: post - pre", pos = 4, font = 4, cex = cex * 1.1)
  text(xlim[1], max(rows_ctr) + 1.3, "Controlled effect: intervention change - control change", pos = 4, font = 4, cex = cex * 1.1)
  addpoly(res_int,  row = min(rows_int) - 1.2, mlab = list(pooled_label(res_int,  "Pooled")), cex = cex, efac = 1.3)
  addpoly(res_ctl,  row = min(rows_ctl) - 1.2, mlab = list(pooled_label(res_ctl,  "Pooled")), cex = cex, efac = 1.3)
  addpoly(res_ctrl, row = min(rows_ctr) - 1.2, mlab = list(pooled_label(res_ctrl, "Pooled")), cex = cex, efac = 1.3)
  text(xlim[1], -0.6, pos = 4, cex = cex * 0.9,
       bquote(paste("Intervention vs control arms: ", Q[M], " = ", .(fmt(res_arm$QM, 1)), ", df = 1, ", .(pstr(res_arm$QMp)),
                    ".  Assumed pre/post ", italic(r), " = ", .(R_PREPOST), ".")))
}

agg_png(file.path(DERIV_DIR, "fig_prepost_forest.png"), width = 8.5, height = 7, units = "in", res = 600, background = "white")
plot_prepost_forest(); invisible(dev.off())
pdf(file.path(DERIV_DIR, "fig_prepost_forest.pdf"), width = 8.5, height = 7)
plot_prepost_forest(); invisible(dev.off())

plot_prepost_funnel <- function() funnel(res_ctrl, main = "Controlled pre/post effect", xlab = "Hedges' g")
agg_png(file.path(DERIV_DIR, "figS_prepost_funnel.png"), width = 5, height = 5, units = "in", res = 300, background = "white")
plot_prepost_funnel(); invisible(dev.off())
pdf(file.path(DERIV_DIR, "figS_prepost_funnel.pdf"), width = 5, height = 5)
plot_prepost_funnel(); invisible(dev.off())

## =========================================================================
## 6. Console summary
## =========================================================================
cat("\n== Pre/post meta-analysis (BCT), assumed r =", R_PREPOST, "==\n")
print(as.data.frame(models %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
cat("\nSensitivity to assumed pre/post r (controlled effect):\n")
print(as.data.frame(sens %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
cat("\nLeave-one-out (controlled effect):\n")
print(as.data.frame(l1o %>% select(omitted, estimate, ci.lb, ci.ub, I2) %>% mutate(across(where(is.numeric), ~ signif(.x, 3)))), row.names = FALSE)
