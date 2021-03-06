simulate.linmod <- function(seed, n){
  intercept <- 4
  slope <- -5
  sigma <- 1
  set.seed(seed)
  x <- rnorm(n)
  eps <- rnorm(n, 0, sigma)
  y <- eps + intercept+slope*x
  Data <- list(y=y, x=x)
  Par <- list(b0=intercept, b1=0, logsigma=0)
  return(list(Data=Data, Par=Par))
}



run.linmod.iter <- function(ii, nobs=100, savefiles=TRUE){
  library(TMB)
  library(DHARMa)
  library(INLA)
  library(dplyr)
  library(tidyr)
  library(R.utils)
  library(goftest)
  dyn.load(dynlib("models/linmod"))

  ## simulate data with these parameters
  message(ii, ": Simulating data...")
  out <- simulate.linmod(ii, nobs)
  dat0 <- out$Data
  ## Add an outlier to each group
  dat1 <- dat0
  #ind <- which(!duplicated(dat0$group))
  set.seed(ii)
  #dat1$y[ind] <- dat1$y[ind]+sample(c(-2,2), size=length(ind), replace=TRUE)
  #add lognormal error
  dat1$y <- dat1$y * exp(rnorm(nobs,0,1))
  message(ii, ": Optimizing two competing models...")
  ## H0: correctly specified
  obj0 <- MakeADFun(dat0, out$Par, DLL = 'linmod')
  trash <- obj0$env$beSilent()
  opt0 <- nlminb(obj0$par, obj0$fn, obj0$gr)
  opt0 <- add_aic(opt0, n=length(dat0$y))
  sdr0 <- sdreport(obj0, getJointPrecision=TRUE)
  rep0 <- obj0$report(obj0$env$last.par.best)

  ## H1: lognormal error added
  obj1 <- MakeADFun(dat1, out$Par, DLL = 'linmod')#, map=list(b1=factor(NA)))
  trash <- obj1$env$beSilent()
  opt1 <- nlminb(obj1$par, obj1$fn, obj1$gr)
  opt1 <- add_aic(opt1, n=length(dat1$y))
  sdr1 <- sdreport(obj1, getJointPrecision=TRUE)
  rep1 <- obj1$report(obj1$env$last.par.best)
  ## Save MLEs to test for properties. These are the true pars as
  ## parameterized in the TMB model
  truepars <- c(4,-5, log(1))
  mles <- rbind(
    data.frame(version='m0', rep=ii, mle=opt0$par,
               par=names(obj0$par), true=truepars),
    data.frame(version='m1', rep=ii, mle=opt1$par,
               par=names(obj1$par), true=truepars))
  dir.create('results/linmod_mles', showWarnings=FALSE)
  if(savefiles) saveRDS(mles, file=paste0('results/linmod_mles/mles_', ii, '.RDS'))


  message(ii, ": Calculating residuals..")
  ## all but generic defaults to pearson's residuals. True, but
  ## Cole undid this to keep things consistent
  ## osa0 <- (dat0$y-rep0$mu)/exp(opt0$par['logsigma'])#calculate.osa(obj0, methods=c('gen','fg', 'osg', 'cdf'), observation.name='y')
  ## osa1 <- (dat1$y-rep1$mu)/exp(opt1$par['logsigma'])#calculate.osa(obj1, methods=c('gen','fg', 'osg', 'cdf'), observation.name='y')
  osa0 <- calculate.osa(obj0, methods=c('gen','fg', 'osg', 'cdf'), observation.name='y')
  osa1 <- calculate.osa(obj1, methods=c('gen','fg', 'osg', 'cdf'), observation.name='y')

  ## DHARMa resids, both conditional and unconditional
  ## hack to get this to evaluate in a function
  expr <- expression(obj$simulate()$y)
  sim0_cond <-
    calculate.dharma(obj0, expr, obs=dat0$y, fpr=rep0$mu)
  sim0_uncond <- sim0_cond
  sim1_cond <-
    calculate.dharma(obj1, expr, obs=dat1$y, fpr=rep1$mu)
  sim1_uncond <- sim1_cond

  sim0_parcond <- calculate.jp(obj0, sdr0, opt0, dat0$y, 'y', fpr=rep0$mu, random = FALSE)
  sim1_parcond <- calculate.jp(obj1, sdr1, opt1, dat1$y, 'y', fpr=rep1$mu, random = FALSE)

  ## Combine together in tidy format for analysis and plotting later
  r0 <- data.frame(model='linmod', replicate=ii, y=dat0$y, x=dat0$x,
                   ypred=rep0$mu, version='m0',
                   ## pearsons = osa0,
                   osa.cdf = osa0$cdf, osa.gen = osa0$gen,
                   osa.fg=osa0$fg, osa.osg=osa0$osg,
                   sim_cond=sim0_cond$resids,
                   ## sim_uncond=sim0_uncond$resids,
                   sim_parcond=sim0_parcond$resids,
                   runtime_cond=sim0_cond$runtime,
                   runtime_parcond=sim0_parcond$runtime,
                   runtime.cdf=osa0$runtime.cdf,
                   runtime.fg=osa0$runtime.fg,
                   runtime.osg=osa0$runtime.osg,
                   runtime.gen=osa0$runtime.gen,
                   maxgrad=max(abs(obj0$gr(opt0$par))),
                   AIC=opt0$AIC, AICc=opt0$AICc)
  r1 <- data.frame(model='linmod', replicate=ii, y=dat1$y, x=dat1$x,
                   ypred=rep1$mu, version='m1',
                   ## pearsons = osa1,
                   osa.cdf = osa1$cdf, osa.gen = osa1$gen,
                   osa.fg=osa1$fg, osa.osg=osa1$osg,
                   sim_cond=sim1_cond$resids,
                   ## sim_uncond=sim1_uncond$resids,
                   sim_parcond=sim1_parcond$resids,
                   runtime_cond=sim1_cond$runtime,
                   runtime_parcond=sim1_parcond$runtime,
                   runtime.cdf=osa1$runtime.cdf,
                   runtime.fg=osa1$runtime.fg,
                   runtime.osg=osa1$runtime.osg,
                   runtime.gen=osa1$runtime.gen,
                   maxgrad=max(abs(obj1$gr(opt1$par))),
                   AIC=opt1$AIC, AICc=opt1$AICc)
  resids <- rbind(r0, r1)

  ## Calculate p-values. Dharma and JPdone already above
  ## osa.pvals0 <- ad.test(osa0, 'pnorm', estimated = TRUE)$p.value #calc.osa.pvals(osa0)
  ## osa.pvals0 <- list(fg = osa.pvals0, osg = osa.pvals0,
  ##                    cdf = osa.pvals0, gen = osa.pvals0)
  ## osa.pvals1 <- ad.test(osa1, 'pnorm', estimated = TRUE)$p.value #calc.osa.pvals(osa1)
  ## osa.pvals1 <- list(fg = osa.pvals1, osg = osa.pvals1,
  ##                    cdf = osa.pvals1, gen = osa.pvals1)
    ## Calculate p-values. Dharma and JPdone already above
  osa.pvals0 <- calc.osa.pvals(osa0)
  osa.pvals1 <- calc.osa.pvals(osa1)


  pvals0 <- make.pval.df(osa.pvals0, sim0_cond, sim0_uncond, sim0_parcond)
  pvals0$version <- 'm0'
  pvals1 <- make.pval.df(osa.pvals1, sim1_cond, sim1_uncond, sim1_parcond)
  pvals1$version <- 'm1'
  pvals <- rbind(pvals0, pvals1)
  pvals$replicate <- ii; pvals$model <- 'linmod'

  ## No random effects so drop the parcond and uncond ones,
  ## dummies added above
  #pvals <- pvals %>% filter(!method %in% c('parcond', 'uncond'))
  pvals <- pvals %>% filter(!method %in% c('uncond', 'osa.osg', 'osa.cdf', 'osa.gen'))
  #resids <- resids %>% dplyr::select(-c('sim_parcond', 'sim_uncond'))

  ## save to file in case it crashes can recover what did run
  if(savefiles){
    dir.create('results/linmod_pvals', showWarnings=FALSE)
    dir.create('results/linmod_resids', showWarnings=FALSE)
    saveRDS(pvals, file=paste0('results/linmod_pvals/pvals_', ii, '.RDS'))
    saveRDS(resids, file=paste0('results/linmod_resids/resids_', ii, '.RDS'))
  }
  if(ii==1 & savefiles){
    message("Making plots for replicate 1...")
    library(ggplot2)
    resids.long <- resids %>%
     ## pivot_longer(c('pearsons', 'sim_cond', 'sim_parcond')) %>%
      pivot_longer(c('osa.cdf', 'osa.gen', 'osa.fg', 'osa.osg',
                     'sim_cond')) %>%
      filter(!is.na(value))
    theme_set(theme_bw())
    ## Plot of data
    g <- data.frame(x=dat0$x,y=dat0$y) %>% ggplot(aes(x,y))+ geom_point()
    ggsave('plots/linmod_simdata.png',g, width=7, height=4, units='in')
    ## plot of resids
    g <- ggplot(resids.long, aes(x, y=value)) +
      geom_point() + facet_grid(version~name) +
      labs(x='x', y='Residual')
    ggsave('plots/linmod_resids_by_x.png', g, width=9, height=6)
    g <- GGally::ggpairs(resids, columns=7:10, mapping=aes(color=version), title='Random Walk')
    ggsave('plots/linmod_resids_pairs.png', g, width=7, height=5)
    ## Plot of  DHARMa simulated data look like
    ff <- function(x, v, re) data.frame(x=dat0$x, x$sims,  version=v, method=re)
    g <- rbind(ff(sim0_cond, 'm0', 'cond'),
                   ff(sim1_cond, 'm1', 'cond')) %>%
      pivot_longer(cols=c(-x, -version, -method), names_prefix="X",
                   names_to='replicate', values_to='y') %>%
      mutate(replicate=as.numeric(replicate)) %>%
      ggplot(aes(x,y)) +
      geom_point(alpha=.5, pch='.') +
      facet_grid(version~method)
    g <- g+geom_point(col='red', alpha=.5, data=rbind(data.frame(dat0), data.frame(dat1)))
    ggsave('plots/linmod_simdata.png', g, width=9, height=6)
  }
  return(invisible(list(pvals=pvals, resids=resids, mles=mles)))
}
