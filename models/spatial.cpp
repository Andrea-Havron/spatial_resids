// Spatial poisson GLMM on a grid, with exponentially decaying correlation function
#include <TMB.hpp>

/* Simulate from tweedie distribution *///from glmmTMB 
template<class Type>
Type rtweedie(Type mu_, Type phi_, Type p_){
  double mu = asDouble(mu_);
  double Phi = asDouble(phi_);
  double p = asDouble(p_);
  // Copied from R function tweedie::rtweedie
  double lambda = pow(mu, 2. - p) / (Phi * (2. - p));
  double alpha  = (2. - p) / (1. - p);
  double gam = Phi * (p - 1.) * pow(mu, p - 1.);
  int N = (int) rpois(lambda);
  double ans = rgamma(N, -alpha /* shape */, gam /* scale */).sum();
  return ans;
}

enum valid_family{
  gaussian_family = 000,
  Gamma_family = 100,
  Poisson_family = 200,
  lognormal_family = 300,
  Tweedie_family = 400
};


enum  valid_link{
  log_link = 0,
  logit_link = 1,
  identity_link = 2, 
  probit_link = 3
};

//inverse links *///from glmmTMB 
template<class Type>
Type inverse_linkfun(Type eta, int link){
  Type ans;
  switch(link){
    case log_link:
      ans = exp(eta);
      break;
    case identity_link:
      ans = eta;
      break;
    case logit_link:
      ans = invlogit(eta);
      break;
    case probit_link:
      ans = pnorm(eta);
      break;
    default:
      error("Link not implemented");
  } // end switch
  return ans; 
}

template<class Type>
Type objective_function<Type>::operator() ()
{
  using namespace R_inla;
  using namespace density;
  using namespace Eigen;

  DATA_VECTOR(y);
  DATA_MATRIX(X);
  DATA_MATRIX(dd);
  DATA_SCALAR(nu);
  DATA_IVECTOR(v_i);
  DATA_INTEGER(simRE);
  DATA_INTEGER( family );
  DATA_INTEGER( link );
  DATA_INTEGER( reStruct );
  DATA_STRUCT(spde,spde_t);

  PARAMETER_VECTOR(beta);
  PARAMETER(theta);      
  PARAMETER(log_tau);
  PARAMETER(log_kappa);
  PARAMETER_VECTOR(omega);  
  DATA_VECTOR_INDICATOR( keep, y );

  int i,j; 
  int n = y.size();

  Type tau = exp(log_tau);
  Type kappa = exp(log_kappa);

  Type nll = 0.0;

  Type marg_sp_sd = 1/(2*sqrt(M_PI)*exp(log_kappa)*exp(log_tau));

  //Spatial Likelihood
 if(reStruct==00){
  matrix<Type> cov(n,n); 
   for (i=0;i<n;i++){
       cov(i,i)=Type(1);
       for ( j=0;j<i;j++){
         cov(i,j)=matern(dd(i,j), sqrt(8)/kappa, Type(nu)); //nu=0.5: exponential decay; nu=1: approx. gaussian decay 
         cov(j,i)=cov(i,j);
      }
    }
    REPORT(cov);
    nll+= SCALE(MVNORM(cov), marg_sp_sd)(omega);
    if(simRE == 1){
      SIMULATE{
        omega = MVNORM(cov).simulate() * marg_sp_sd;
        REPORT(omega);
      }
    }
  }
  if(reStruct==10){
    SparseMatrix<Type> Q = Q_spde(spde,kappa);
    nll += SCALE( GMRF(Q), 1/tau )(omega);        
    if(simRE == 1){
      SIMULATE{
        GMRF(Q).simulate(omega);
        omega = omega/tau;
        REPORT(omega);
      }
    }
    REPORT(Q);
  }
  
  vector<Type> Xbeta = X*beta;  
  vector<Type> eta(n);
  vector<Type> mu(n);
  Type cdf;
  //Data Likelihood
  for(int i=0; i<n; i++){    
    eta(i) = Xbeta(i) + omega(v_i(i));

    mu(i) = inverse_linkfun(eta(i), link);

    switch(family){
      case gaussian_family:
        nll -= dnorm(y(i), mu(i), exp(theta), true);
        SIMULATE{
          y(i) = rnorm(mu(i), exp(theta));
        }
        break;
      case Gamma_family:
        //shape = 1/CV^2; scale = mean*CV^2
        nll -= keep(i) * dgamma( y(i), 1/exp(2*theta), mu(i)*exp(2*theta), true);
        cdf = squeeze( pgamma(y(i), 1/exp(2*theta), mu(i)*exp(2*theta)) );
        nll -= keep.cdf_lower(i) * log( cdf );
        nll -= keep.cdf_upper(i) * log( 1.0 - cdf );
        SIMULATE{
          y(i) = rgamma( 1/exp(2*theta), mu(i)*exp(2*theta) );
        }
        break;
      case Poisson_family:
        nll -= keep(i) * dpois(y(i), mu(i), true);
        cdf = squeeze( ppois(y(i), mu(i)) );
        nll -= keep.cdf_lower(i) * log( cdf );
        nll -= keep.cdf_upper(i) * log( 1.0 - cdf );
        SIMULATE{
          y(i) = rpois(mu(i));
        }
        break;
      case lognormal_family:
        nll -= keep(i) * dnorm(y(i), mu(i) - exp(2*theta)/2, exp(theta), true) - log(y(i));
        cdf = squeeze( pnorm(log(y(i)), mu(i) - exp(2*theta)/2, exp(theta)) );
        nll -= keep.cdf_lower(i) * log( cdf );
        nll -= keep.cdf_upper(i) * log( 1.0 - cdf );
        SIMULATE{
          y(i) = exp( rnorm( mu(i) - exp(2*theta)/2, exp(theta)) );
        }
        break;
      default:
        error("Family not supported");
    }
  } 

  SIMULATE{
    REPORT(y);
  }

  REPORT(marg_sp_sd);
  REPORT(eta);
  REPORT(mu);
  REPORT(nll);

  return nll;

}
