message("Loading global functions...")

make.pval.df <- function(osa, sim_cond, sim_uncond, sim_parcond){
  pvals <- rbind(
    data.frame(method='parcond', test='outlier', pvalue=sim_parcond$outlier),
    data.frame(method='cond', test='outlier', pvalue=sim_cond$outlier),
    data.frame(method='uncond', test='outlier', pvalue=sim_uncond$outlier),
    data.frame(method='parcond', test='disp', pvalue=sim_parcond$disp),
    data.frame(method='cond', test='disp', pvalue=sim_cond$disp),
    data.frame(method='uncond', test='disp', pvalue=sim_uncond$disp),
    data.frame(method='parcond', test='GOF.ks', pvalue=sim_parcond$pval.ks),
    data.frame(method='cond', test='GOF.ks', pvalue=sim_cond$pval.ks),
    data.frame(method='uncond', test='GOF.ks', pvalue=sim_uncond$pval.ks),
    data.frame(method='osa.fg', test='GOF.ks', pvalue=osa$fg.ks),
    data.frame(method='osa.osg', test='GOF.ks', pvalue=osa$osg.ks),
    data.frame(method='osa.cdf', test='GOF.ks', pvalue=osa$cdf.ks),
    data.frame(method='osa.gen', test='GOF.ks', pvalue=osa$gen.ks),
    data.frame(method='parcond', test='GOF.ad', pvalue=sim_parcond$pval.ad),
    data.frame(method='cond', test='GOF.ad', pvalue=sim_cond$pval.ad),
    data.frame(method='uncond', test='GOF.ad', pvalue=sim_uncond$pval.ad),
    data.frame(method='osa.fg', test='GOF.ad', pvalue=osa$fg.ad),
    data.frame(method='osa.osg', test='GOF.ad', pvalue=osa$osg.ad),
    data.frame(method='osa.cdf', test='GOF.ad', pvalue=osa$cdf.ad),
    data.frame(method='osa.gen', test='GOF.ad', pvalue=osa$gen.ad))
  return(pvals)
}


calc.sac <- function(x, w){
  y <- NA
  if(is.numeric(x)){
    ## only test for positive correlationa
    y <- ape::Moran.I(x, w, alternative = 'greater')$p.value
  }
  return(y)
}

calc.osa.pvals <- function(osa){
  fg.ks <- osg.ks <- cdf.ks <- gen.ks <- NA
  fg.ad <- osg.ad <- cdf.ad <- gen.ad <- NA
  if(is.numeric(osa$fg)){
    fg.ad <- goftest::ad.test(osa$fg,'pnorm', estimated = TRUE)$p.value
    fg.ks <- suppressWarnings(ks.test(osa$fg,'pnorm')$p.value)
  }
  if(is.numeric(osa$osg)){
    osg.ad <- goftest::ad.test(osa$osg,'pnorm', estimated = TRUE)$p.value
    osg.ks <- suppressWarnings(ks.test(osa$osg,'pnorm')$p.value)
  }
  if(is.numeric(osa$cdf)){
    cdf.ad <- goftest::ad.test(osa$cdf,'pnorm', estimated = TRUE)$p.value
    cdf.ks <- suppressWarnings(ks.test(osa$cdf,'pnorm')$p.value)
  }
  if(is.numeric(osa$gen)){
    gen.ad <- goftest::ad.test(osa$gen,'pnorm', estimated = TRUE)$p.value
    gen.ks <- suppressWarnings(ks.test(osa$gen,'pnorm')$p.value)
  }
  return(list(fg.ks=fg.ks, osg.ks=osg.ks, cdf.ks=cdf.ks, gen.ks=gen.ks,
              fg.ad=fg.ad, osg.ad=osg.ad, cdf.ad=cdf.ad, gen.ad=gen.ad))
}


calc.dharma.pvals <-
  function(dharma, alternative = c("two.sided", "greater", "less")){
  ## Extract p-values calculated by DHARMa
  ##
  ## Note: Type binomial for continuous, if integer be careful. Not
  ## sure if we want two-sided for dispersion? Using defaults for
  ## now.
  ## AMH: change to alternative = 'greater' when testing for overdispersion in positive only distributions
  ## AMH: Add significance tests
  alternative <- match.arg(alternative)
  disp <- testDispersion(dharma, alternative, plot=FALSE)
  outlier <- testOutliers(dharma, alternative,
                          margin = 'upper', type='binomial', plot=FALSE)
  resids <- residuals(dharma, quantileFunction = qnorm, outlierValues = c(-7,7))
  pval.ks <-
    suppressWarnings(ks.test(dharma$scaledResiduals,'punif')$p.value)
  pval.ad <- goftest::ad.test(resids,'pnorm', estimated = TRUE)$p.value
  return(list(disp=disp, outlier=outlier, pval.ks=pval.ks, pval.ad=pval.ad))
}


## Function to simulate parameters from the joint precisions
## matrix (fixed + random effects). Modified from
## FishStatsUtils::simulate_data
rmvnorm_prec <- function(mu, prec ) {
  ##set.seed( random_seed )
  z = matrix(rnorm(length(mu)), ncol=1)
  L = Matrix::Cholesky(prec, super=TRUE)
  z = Matrix::solve(L, z, system = "Lt") ## z = Lt^-1 %*% z
  z = Matrix::solve(L, z, system = "Pt") ## z = Pt    %*% z
  z = as.vector(z)
  return(mu + z)
}

## Quick fn to check for failed runs by looking at results output
## that doesn't exist
which.failed <- function(Nreps){
  success <- gsub('results/spatial_pvals/pvals_|.RDS', "", x=fs) %>%
    as.numeric()
  fail <- which(! 1:Nreps %in% success)
  fail
}


add_aic <- function(opt,n){
  opt$AIC <- TMBhelper::TMBAIC(opt, n=Inf)
  opt$AICc <- TMBhelper::TMBAIC(opt, n=n)
  opt$BIC <- TMBhelper::TMBAIC(opt, p=log(n))
  opt
}

calculate.jp <- function(obj, sdr, opt, obs, data.name, fpr, N=1000, random = TRUE,
                         alternative = c("two.sided", "greater","less")){
  alternative = match.arg(alternative)
  t0 <- Sys.time()
  joint.mle <- obj$env$last.par.best
  if(random){
  test <- tryCatch(Matrix::Cholesky(sdr$jointPrecision, super=TRUE),
                   error=function(e) 'error')
  if(is.character(test)){
    warning("Joint-Precision approach failed b/c Chol factor failed")
    return(list(sims=NA, runtime=NA, resids=NA, disp=NA, outlier=NA,
                         pval.ks=NA, pval.ad=NA))
  }
  jp.sim <- function(){
    newpar <- rmvnorm_prec(mu=joint.mle, prec=sdr$jointPrecision)
    obj$env$data$simRE <- 0 # turn off RE simulation
    obj$simulate(par=newpar)[[data.name]]
  }
  ## newpars <- replicate(1000, {rmvnorm_prec(mu=joint.mle, prec=sdr$jointPrecision)})
  ## pairs(t(newpars))
  newpar <- rmvnorm_prec(mu=joint.mle, prec=sdr$jointPrecision)
  } else {
    jp.sim <- function(){
      newpar <- mvtnorm::rmvnorm(1, sdr$par.fixed, sdr$cov.fixed)
      obj$env$data$simRE <- 0 # turn off RE simulation
      obj$simulate(par=newpar)[[data.name]]
    }
  }
  tmp <- replicate(N, {jp.sim()})
  if(any(is.nan(tmp))){
    warning("NaN values in JP simulated data")
    return(list(sims=NA, runtime=NA, resids=NA, disp=NA, outlier=NA,
                         pval.ks=NA, pval.ad=NA))
  }
  dharma <- createDHARMa(tmp, obs, fittedPredictedResponse=fpr)
  resids <- residuals(dharma, quantileFunction = qnorm, outlierValues = c(-7,7))
  runtime <- as.numeric(Sys.time()-t0, 'secs')
  disp <- testDispersion(dharma, alternative = alternative, plot=FALSE)
  outlier <- testOutliers(dharma, alternative = alternative,
                          margin = 'upper', type='binomial', plot=FALSE)
  pval.ks <-
    suppressWarnings(ks.test(dharma$scaledResiduals,'punif')$p.value)
  pval.ad <- goftest::ad.test(resids,'pnorm', estimated = TRUE)$p.value
  return(list(sims=tmp, runtime=runtime, resids=resids, disp=disp$p.value,
                         outlier=outlier$p.value,
                         pval.ks=pval.ks, pval.ad=pval.ad))
}



calculate.dharma <- function(obj, expr, N=1000, obs, fpr,
                             alternative = c("two.sided", "greater","less")){
  alternative <- match.arg(alternative)
  t0 <- Sys.time()
  tmp <- replicate(N, eval(expr))
  dharma <- createDHARMa(tmp, obs, fittedPredictedResponse = fpr)
  resids <- residuals(dharma, quantileFunction = qnorm,
                      outlierValues = c(-7,7))
  runtime <- as.numeric(Sys.time()-t0, 'secs')
  ## Extract p-values calculated by DHARMa
  ##
  ## Note: Type binomial for continuous, if integer be careful. Not
  ## sure if we want two-sided for dispersion? Using defaults for
  ## now.
  ## AMH: change to alternative = 'greater' when testing for overdispersion in positive only distributions
  ## AMH: Add significance tests
  disp <- testDispersion(dharma, alternative = alternative, plot=FALSE)
  outlier <- testOutliers(dharma, alternative = alternative,
                          margin = 'upper', type='binomial', plot=FALSE)
  pval.ks <-
    suppressWarnings(ks.test(dharma$scaledResiduals,'punif')$p.value)
  pval.ad <- goftest::ad.test(resids,'pnorm', estimated = TRUE)$p.value
  return(list(sims=tmp, resids=resids, disp=disp$p.value,
              outlier=outlier$p.value, pval.ks=pval.ks,
              pval.ad=pval.ad, runtime=runtime))
}

calculate.osa <- function(obj, methods, observation.name,
                          data.term.indicator='keep',
                          Range = c(-Inf,Inf)){
  ## OSA residuals
  fg <- osg <- cdf <- gen <- NA
  runtime.fg <- runtime.osg <- runtime.cdf <- runtime.gen <- NA
  if('fg' %in% methods){
    t0 <- Sys.time()
    fg <- tryCatch(
      oneStepPredict(obj, observation.name=observation.name,
                     method="fullGaussian", trace=FALSE)$residual,
      error=function(e) 'error')
    runtime.fg <- as.numeric(Sys.time()-t0, 'secs')
    if(is.character(fg)){
      warning("OSA Full Gaussian failed")
      fg <- NA; runtime.fg <- NA
    }
  }
  ## one step Gaussian method
  if('osg' %in% methods){
    t0 <- Sys.time()
    osg <- tryCatch(
      oneStepPredict(obj, observation.name=observation.name,
                     data.term.indicator='keep' ,
                     method="oneStepGaussian", trace=FALSE)$residual,
      error=function(e) 'error')
    runtime.osg <- as.numeric(Sys.time()-t0, 'secs')
    if(is.character(osg)){
      warning("OSA one Step Gaussian failed")
      osg <- NA; runtime.osg <- NA
    }
  }
  ## cdf method
  if('cdf' %in% methods){
    t0 <- Sys.time()
    cdf <- tryCatch(
      oneStepPredict(obj, observation.name=observation.name,
                     data.term.indicator='keep' ,
                     method="cdf", trace=FALSE)$residual,
      error=function(e) 'error')
    runtime.cdf <- as.numeric(Sys.time()-t0, 'secs')
    if(is.character(cdf) | any(!is.finite(cdf))){
      warning("OSA cdf failed")
      cdf <- NA; runtime.cdf <- NA
    }
  }
  ## one step Generic method
  if('gen' %in% methods){
    t0 <- Sys.time()
    gen <- tryCatch(
      oneStepPredict(obj, observation.name=observation.name,
                     data.term.indicator='keep' ,
                     range = Range,
                     ##! range = c(0,Inf) only when obs>0 ,
                     method="oneStepGeneric", trace=FALSE)$residual,
      error=function(e) 'error')
    runtime.gen <- as.numeric(Sys.time()-t0, 'secs')
    if(is.character(gen) | (!is.character(gen) & any(!is.finite(gen)))){
      warning("OSA Generic failed")
      gen <- NA; runtime.gen <- NA
    }
  }
  return(list(gen=gen, fg=fg, osg=osg, cdf=cdf,
              runtime.gen=runtime.gen, runtime.fg=runtime.fg,
              runtime.osg=runtime.osg, runtime.cdf=runtime.cdf))
}


