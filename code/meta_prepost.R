####
#### m  e  t  a  a  n  a  l  y  s  i  s
####
#### Analysis of all the studies that
#### look at a breath task performance
#### pre/post intervention.
####
#### There is a subgroup analysis (control vs intervention)
#### where the 2 subgroups are compared to see
#### if intervention is more effective than a control.
####
#### see https://wviechtb.github.io/meta_analysis_books/borenstein2009.html#19)_Subgroup_Analyses

suppressMessages(library(dplyr))
suppressMessages(library(readxl))
suppressMessages(library(metafor))


############################################
#######  load and clean data

import_fname <- "../data/breathpubs_prepost.xlsx"

# setwd("/Users/remy/Google Drive/projects/breathtmr/code")
dat <- readxl::read_excel(import_fname)

dat <- dat %>%
  dplyr::filter(!is.na(mean1)) %>%
  dplyr::filter(study_type == "prepost") %>%
  dplyr::filter(breathtask == "BCT") %>%
  dplyr::filter(author != "Lim") %>%
  dplyr::arrange(desc(control), desc(year), desc(author), desc(study), desc(correlate))
  # dplyr::select(year, author, n, starts_with("mean"), starts_with("sd"), starts_with("sem"))
# sd1 <- subset(dat$sem1, is.na(dat$sd1)) * sqrt(subset(dat$n1, is.na(dat$sd1)))


############################################
#######  run meta-analysis

# convert standard errors to standard deviations
dat$sd1 <- metafor::replmiss(dat$sd1, with(dat, sem1*sqrt(n)))
dat$sd2 <- metafor::replmiss(dat$sd2, with(dat, sem2*sqrt(n)))

# calculate study effect sizes
dat <- metafor::escalc(
    measure="SMD",
    n1i=n, n2i=n,
    # ni=n, # will this work if Ns are the same?? dont'
    m1i=mean2, m2i=mean1,
    sd1i=sd2, sd2i=sd1,
    # r2i, ni, yi, vi, sei,
    data=dat,
    # slab=paste(author, year, sep=", "),
    add=1/2, to="only0", drop00=FALSE, # only relevant for counts
    vtype="UB", var.names=c("yi","vi"),
    add.measure=FALSE, append=TRUE, replace=TRUE)

dat <- as_tibble(dat)

# must be a better way, confused about slab
dat$study <- 1:dim(dat)[1]

# run model for interventions
res_intrv <- metafor::rma.uni(yi=yi, vi=vi, data=dat, method="REML", subset=control==FALSE)

# run model for controls
# res_ctl <- metafor::rma.uni(yi=yi, vi=vi, data=dat, method="REML", subset=control==TRUE)
res_ctl <- metafor::rma.mv(yi=yi, V=vi, random=~1|author/study, data=dat, method="REML", subset=control==TRUE)

# run complete model (just for plotting)
res <- metafor::rma.uni(yi=yi, vi=vi, data=dat, method="REML")

# run model comparing the interventions and controls
# res_mod <- metafor::rma.uni(yi=yi, vi=vi, mods=~control, data=dat, method="REML")
res_mod <- metafor::rma.mv(yi=yi, V=vi, mods=~control, random=~1|author/study, data=dat, method="REML")


# the multilevel model needs I^2 to be manually computed
# see https://www.metafor-project.org/doku.php/tips:i2_multilevel_multivariate
mv_i2 <- function(res, dat) {
    W <- diag(1/dat$vi)
    X <- model.matrix(res)
    P <- W - W %*% X %*% solve(t(X) %*% W %*% X) %*% t(X) %*% W
    i2 <- 100 * sum(res$sigma2) / (sum(res$sigma2) + (res$k-res$p)/sum(diag(P)))
    return(i2)
}
res_ctl$I2 <- mv_i2(res_ctl, subset(dat, control==TRUE))


############################################
#######  visualization

png(file="../results/meta_prepost.png",
    units="in", res=600,
    width=6, height=7,
    bg="white", type="quartz"
)


# get horizontal positions
n_intrv <- sum(!dat$control)
n_ctl <- sum(dat$control)
# subhead_topbuff <- 2 # space to write header, and just room
# subgroup_lowbuff <- 3 # space to write stats underneath, and just room
ypos1 <- c( 3:(2+n_ctl) )
ypos2 <- c( (6+max(ypos1)):(5+max(ypos1)+n_intrv) )
rows <- c(ypos1, ypos2)


# A numerical vector of the form c(bottom, left, top, right) which gives the number of lines of margin to be specified on the four sides of the plot.
# The default is c(5, 4, 4, 2) + 0.1.
# par(mar=c(4,4,2,2))
header_positions <- c(-3.5, -2)
xlim <- c(-7, 4.5)
cex <- .75

slab <- with(dat, paste(author, year, sep=" et al., "))

# rows <- c(3:12, 17:22)
ylim <- c(-1.2, max(rows)+5)

# plot all the studies
forest(res,
    addfit=FALSE,
    # choose y/horizontal positions, separate by 1, start at 1 (1 is right above the bottom line)
    rows=rows, # leave 2 spaces for the combined effects and then a few also for space between the subsets
    xlim=xlim, # horizontal limits of the plot region
    ylim=ylim, # the y-axis limits of the plot
    cex=cex, # character and symbol expansion factor
    efac=c(0,1,1.5),
    # top=3,
    # refline=0.5, # numeric value to specify the location of the vertical ‘reference’ line (the default is 0).
    header=c("Publication", "Hedges g [95% CI]"), # character vector to specify the left and right headings
    xlab="Hedges g\n(standardized post-pre)", # title for the x-axis
    mlab="Total", # label to the summary estimate
    slab=slab,
    # at=seq(-.2, 1.2, by=.2), # position of the x-axis tick marks and corresponding labels
    # steps #the number of tick marks for the x-axis (the default is 5). Ignored when the positions are specified via the at argument.
    # addpred, 
    ilab=cbind(dat$intervention, dat$n),
    ilab.xpos=header_positions,
    ilab.pos=4,
)
text(min(xlim), max(ypos1)+1.5, "Control", pos=4, font=4, cex=1)
text(min(xlim), max(ypos2)+1.5, "Intervention", pos=4, font=4, cex=1)

text(min(header_positions), max(rows)+4, "Method", pos=4, font=2, cex=cex)
# text(header_positions[2], max(rows)+4, "Length (wk)", pos=4, font=2, cex=cex)
text(max(header_positions), max(rows)+4, expression(italic("N")), pos=4, font=2, cex=cex)

# add text for the test of subgroup differences
text(min(xlim), -1.2, pos=4, cex=0.75, bquote(paste(
    bold("Intervention vs Control: "),
    Q[M], " = ", .(formatC(res_mod$QM, digits=1, format="f")),
    ", df = ", .(res_mod$p - 1),
    " (p ", .(metafor:::.pval(res$QEp, digits=3, showeq=TRUE, sep=" ", add0=FALSE)), ")"
)))


mlabfun <- function(res) {
   list(bquote(paste(
    bold("Total effect: "),
    "Z = ", .(formatC(res$zval, digits=2, format="f")),
    " (p ", .(metafor:::.pval(res$pval, digits=3, showeq=TRUE, sep=" ", add0=FALSE)), ")")))
}

# add the subgroup effects
metafor::addpoly(res_intrv,
    row=min(ypos2)-1.5,
    mlab=mlabfun(res_intrv),
    cex=cex, efac=1.5,
    # width=c(4,5,4), # optional integer to manually adjust the width of the columns for the annotations
)
metafor::addpoly(res_ctl,
    row=min(ypos1)-1.5,
    # mlab="Combined",
    mlab=mlabfun(res_ctl),
    cex=cex, efac=1.5,
)

compile_hetero_string <- function(res) {
    bquote(paste(
        "Heterogeneity: ",
        I^2, " = ", .(formatC(res$I2, digits=0, format="f")), "%; ",
        tau^2, " = ", .(formatC(res$tau2, digits=1, format="f")), "; ",
        "Q = ", .(formatC(res$QE, digits=1, format="f")),
        ", df = ", .(res$k - res$p),
        " (p ", .(metafor:::.pval(res$QEp, digits=3, showeq=TRUE, sep=" ", add0=FALSE)), ")"
    ))
}
text(min(xlim), min(ypos2)-2.5, pos=4, font=1, cex=.7, compile_hetero_string(res_intrv))
text(min(xlim), min(ypos1)-2.5, pos=4, font=1, cex=.7, compile_hetero_string(res_ctl))

title("Breath Counting Task accuracy\npre/post intervention")

dev.off()


# # png(file="./plot.png", width=600, height=350)
# header_positions <- c(-2.5, -2)
# metafor::forest(x=res,
#     annotate=TRUE,
#     header="Publication", # or just True for "Study"
#     top=3,
#     # ilab=cbind(dat$intervention, dat$intervention_length),
#     # ilab.xpos=header_positions,
#     cex=.75,
#     # mlab="",
#     # xlim=c(-4, 2),
# )
# # op <- par(cex=.75, font=2)
# # text(mean(header_positions), 7.5, "Intervention")
# # text(header_positions, 7, c("name", "length"))
# # par(op)
# # dev.off()

# # funnel(res, main="Standard Error")

