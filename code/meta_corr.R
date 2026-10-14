####
#### m  e  t  a  a  n  a  l  y  s  i  s
####
#### Analysis of all the studies that
#### correlate a breath counting task
#### with other stuff.
####
#### There is a subgroup analysis
#### that looks separately at measures
#### of mindfulness, wellbeing, and executive function.

suppressMessages(library(dplyr))
suppressMessages(library(readxl))
suppressMessages(library(metafor))

############################################
#######  load and clean data

import_fname <- "../data/breathpubs_corr.xlsx"

dat <- readxl::read_excel(import_fname)


dat <- dat %>%
  dplyr::filter(!is.na(r)) %>%
  dplyr::filter(breathtask == "BCT") %>%
  # dplyr::filter(substr(correlate,1,5)!="FFMQ-") %>%
  dplyr::mutate(newstudy = ifelse(is.na(study), 1, study)) %>%
  dplyr::rowwise() %>% 
  dplyr::mutate(newr = r * ifelse(reverse, -1, 1)) %>%
  # dplyr::mutate(newr = r * (if(reverse) -1 else 1)) %>%
  dplyr::arrange(category, desc(year), desc(author), desc(study), desc(correlate))

# # create a unique identifier column, different samples within each study
# # (a bit confused bc I think slab does that but I don't see it anywhere)
# # dat$study <- dat$study %>% tidyr::replace_na(1)
dat$sample <- with(dat, paste(author, year, newstudy, sep=", "))



############################################
#######  run meta-analysis

# calculate effect sizes
dat <- metafor::escalc(
    measure="COR",
    ni=n, ri=newr,
    data=dat,
    # slab=paste(author, year, sep=" et al., "),
    add=1/2, to="only0", drop00=FALSE, # only relevant for counts
    vtype="LS", var.names=c("yi","vi"),
    add.measure=FALSE, append=TRUE, replace=TRUE)

dat <- as_tibble(dat)

# run subgroup mindfulness model
res_mf <- metafor::rma.mv(yi=yi, V=vi, random=~1|author/sample, data=dat, method="REML", subset=category=="mindfulness")
# res_mf <- metafor::rma.uni(yi=yi, vi=vi, data=dat, method="REML", subset=category=="mindfulness")
# run subgroup wellbeing model
res_wb <- metafor::rma.mv(yi=yi, V=vi, random=~1|author/sample, data=dat, method="REML", subset=category=="wellbeing")
# res_wb <- metafor::rma.uni(yi=yi, vi=vi, data=dat, method="REML", subset=category=="wellbeing")
# run subgroup executive function model
res_ef <- metafor::rma.mv(yi=yi, V=vi, random=~1|author/sample, data=dat, method="REML", subset=category=="EF")
# res_ef <- metafor::rma.uni(yi=yi, vi=vi, data=dat, method="REML", subset=category=="EF")

# run complete model (just for plotting)
res <- metafor::rma.uni(yi=yi, vi=vi, data=dat, method="REML")


############################################
#######  visualization

png(file="../results/meta_correlations.png",
    units="in", res=600,
    width=6.5, height=10,
    bg="white", type="quartz"
)


# get horizontal positions
n_ef <- sum(dat$category=="EF")
n_mf <- sum(dat$category=="mindfulness")
n_wb <- sum(dat$category=="wellbeing")
ypos1 <- c( 3:(2+n_ef) )
ypos2 <- c( (5+tail(ypos1,1)):(4+tail(ypos1,1)+n_mf) )
ypos3 <- c( (5+tail(ypos2,1)):(4+tail(ypos2,1)+n_wb) )
ypos <- c(ypos1, ypos2, ypos3)

header_positions <- c(-1.5, -.7)
xlim <- c(-3,2.5)
cex <- .75

forest(res,
    addfit=FALSE,
    # choose y/horizontal positions, separate by 1, start at 1 (1 is right above the bottom line)
    rows=ypos, # leave 2 spaces for the combined effects and then a few also for space between the subsets
    xlim=xlim, # horizontal limits of the plot region
    ylim=c(-1.2,tail(ypos,1)+5), # the y-axis limits of the plot
    cex=cex, # character and symbol expansion factor
    efac=c(0,1,1.5),
    slab=dat$sample,
    # top=3,
    # refline=0.5, # numeric value to specify the location of the vertical ‘reference’ line (the default is 0).
    header=c("Publication", "r [95% CI]"), # character vector to specify the left and right headings
    xlab="r", # title for the x-axis
    mlab="Total", # label to the summary estimate
    # at=seq(-.5, 1, by=.5), # position of the x-axis tick marks and corresponding labels
    # steps=5, #the number of tick marks for the x-axis (the default is 5). Ignored when the positions are specified via the at argument.
    # addpred, 
    ilab=cbind(dat$correlate, dat$n),
    ilab.pos=4,
    ilab.xpos=header_positions,
)
text(xlim[1], tail(ypos1,1)+1.5, "Executive function", pos=4, font=4, cex=1)
text(xlim[1], tail(ypos2,1)+1.5, "Mindfulness", pos=4, font=4, cex=1)
text(xlim[1], tail(ypos3,1)+1.5, "Psychological wellbeing", pos=4, font=4, cex=1)
text(header_positions[1], tail(ypos,1)+4, "Correlate", pos=4, font=2, cex=cex)
text(header_positions[2], tail(ypos,1)+4, expression(italic("N")), pos=4, font=2, cex=cex)

# text("header_ .positions[2]", tail(ypos,1)+4, "N", pos=4, font=2, cex=cex)

# add the subgroup effects
metafor::addpoly(res_ef, row=ypos1[1]-1.5,
    mlab="Combined", cex=1, efac=1.5,
    # width=c(4,5,4), # optional integer to manually adjust the width of the columns for the annotations
)
metafor::addpoly(res_mf, row=ypos2[1]-1.5,
    mlab="Combined", cex=1, efac=1.5)
metafor::addpoly(res_wb, row=ypos3[1]-1.5,
    mlab="Combined", cex=1, efac=1.5)

title("Breath Counting Task accuracy\nrelated to psychological constructs")


dev.off()
