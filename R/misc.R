# Half-vectorisation of matrix x
#' @keywords internal
vech <- function(x) x[lower.tri(x, T)]

# check if a matrix is NOT positive semi definite
#' @keywords internal
is.not.SPD <- function(x) any(eigen(x)$values < 0) | det(x) <= 0

# This is only for printed summaries
#' @keywords internal
long.formula.to.print <- function(x, OPT){
  ac <- as.character(x)
  if(OPT == 1) 
    return(paste(ac[1], ac[3]))
  else
    return(paste(ac[2], ac[1], ac[3]))
}

# Neatened family names for printing
#' @keywords internal
neat.family.name <- function(f){
  switch(f,
         gaussian = "Gaussian",
         poisson = "Poisson",
         binomial = "Binomial",
         negbin = "Negative binomial",
         genpois = "Generalised Poisson",
         Gamma = "Gamma")
}

# Parsing input formula
#' @keywords internal
#' @importFrom reformulas splitForm
parseFormula <- function(formula){ 
  split <- reformulas::splitForm(formula, allowFixedOnly = FALSE)
  fixed <- split$fixedFormula
  random <- el(split$reTrmFormulas)
  
  # Parse fixed effects
  response <- as.character(fixed)[2]
  fixed <- as.character(fixed)[3]
  if(grepl('splines\\:\\:|ns\\(|bs\\(', fixed)){
    attr(fixed, 'special') <- 'spline'
    if(grepl('ns\\(', fixed)) attr(fixed, 'spline type') <- 'natural'
    else if(grepl('bs\\(', fixed)) attr(fixed, 'spline type') <- 'basis'
    else stop('Unknown spline type')
  }else{
    attr(fixed, 'special') <- 'none'
  }
  
  # Parse random effects
  random.by <- as.character(random)[3]
  random <- as.character(random)[2]
  if(grepl('splines\\:\\:|ns\\(|bs\\(', random)){
    attr(random, 'special') <- 'spline'
    if(grepl('ns\\(', random)) attr(random, 'spline type') <- 'natural'
    else if(grepl('bs\\(', random)) attr(random, 'spline type') <- 'basis'
    else stop('Unknown spline type')
  }else{
    attr(random, 'special') <- 'none'
  }
  
  return(list(
    response = response,
    fixed = fixed,
    random = random,
    random.by = random.by
  ))
}

# Checking convergence and printing new parameter estimates (if wanted).
#' @keywords internal
converge.check <- function(params.old, params.new, criteria, iter, Omega, verbose){
  
  type <- criteria$type
  # Absolute difference
  diffs.abs <- abs(params.new - params.old)
  # Relative difference
  diffs.rel <- diffs.abs/(abs(params.old) + criteria$tol.den)
  # SAS convergence criterion
  sas.crit <- abs(params.old) >= criteria$threshold
  sas.abs <- diffs.abs < criteria$tol.abs
  sas.rel <- diffs.rel < criteria$tol.rel
  sas.conv <- all(sas.abs[!sas.crit]) & all(sas.rel[sas.crit])
  
  # Check convergence based on user-supplied criterion
  if(type == "abs"){
    converged <- max(diffs.abs) < criteria$tol.abs
  }else if(type == "rel"){
    converged <- max(diffs.rel) < criteria$tol.rel
  }else if(type == "either"){
    converged <- (max(diffs.abs) < criteria$tol.abs) | (max(diffs.rel) < criteria$tol.rel)
  }else if(type == "sas"){
    converged <- sas.conv
  }
  
  if(verbose){
      cat("\n")
      if(iter > 0) cat(sprintf("Iteration %d:\n", iter))
      cat("vech(D):", round(vech(Omega$D), 4), "\n")
      cat("beta:", round(Omega$beta, 4), "\n")
      if(any(unlist(Omega$sigma) != 0)) cat("sigma:", round(unlist(Omega$sigma)[unlist(Omega$sigma) != 0], 4), "\n")
      cat("gamma:", round(Omega$gamma, 4), "\n")
      cat("zeta:", round(Omega$zeta, 4), "\n")
      cat("\n")
      if(iter > 0){
        if(type != "sas") {
          cat("Maximum absolute difference:", round(max(diffs.abs), 4), "for",
              names(params.new)[which.max(diffs.abs)],"\n")
          cat("Maximum relative difference:", round(max(diffs.rel), 4), "for",
              names(params.new)[which.max(diffs.rel)],"\n")
        }else{
          cat("Maximum absolute difference: ", round(max(diffs.abs[!sas.crit]), 4), "for",
              names(params.new)[which.max(diffs.abs[!sas.crit])], "\n")
          cat("Maximum relative difference: ", round(max(diffs.rel[sas.crit]), 4), "for",
              names(params.new)[which.max(diffs.rel[sas.crit])], "\n")
        }
        if(converged) cat(paste0("Converged! (Criteria: ", type, ")."), "\n\n")
      }
      
  }
  
  list(converged = converged,
       diffs.abs = diffs.abs, diffs.rel = diffs.rel)
}

# Don't think this is ever used  -- remove?
# Create appropriately-dimensioned matrix of random effects.
#' @keywords internal
bind.bs<- function(bsplit){
  qmax <- max(sapply(bsplit, length)) # Maximum number of REs across all longitudinal responses.
  # Pad with zeros until each row is of length qmax
  step <- lapply(bsplit, function(b){
    l <- length(b)
    if(l<qmax) b <- c(b, rep(0, (qmax-l)))
    b
  })
  step <- do.call(rbind, step); colnames(step) <- NULL
  as.matrix(step)
}

# Not used, keeping anyway.
# Obtain hessian from a score vector using some differencing method.
#' @keywords internal
numDiff <- function(x, f, ..., method = 'central', heps = 1e-4){
  method <- match.arg(method, c('central', 'forward', 'Richardson'))
  n <- length(x)
  out <- matrix(0, nrow = n, ncol = n)
  hepsmat <- diag(pmax(abs(x), 1) * heps, nrow = n)
  if(method == "central"){
    for(i in 1:n){
      hi <- hepsmat[,i]
      fdiff <- c(f(x + hi, ...) - f(x - hi, ...))
      out[, i] <- fdiff/(2 * hi[i])
    }
  }else if(method == "Richardson"){
    for(i in 1:n){
      hi <- hepsmat[,i]
      fdiff <- c(f(x - 2 * hi, ...) - 8 * f(x - hi, ...) + 8 * f(x + hi, ...) - f(x + 2 * hi, ...))
      out[,i] <- fdiff/(12*hi[i])
    }
  }else{
    f0 <- f(x, ...)
    for(i in 1:n){
      hi <- hepsmat[,i]
      fdiff <- c(f(x + hi, ...) - f0)
      out[,i] <- fdiff/hi[i]
    }
  }
  (out + t(out)) * .5
}

# Construct a block diagonal matrix from LIST of matrices,
# intended to be used in initial condition stage, but could handle
# any list of SQUARE matrices.
#' @keywords internal
bDiag <- function(X){ # X a list of matrices
  K <- length(X)
  # If univariate, just return X[[1]]
  if(K == 1) return(X[[1]])
  # Determine dimensions of constituent block-diagonals
  dims <- sapply(X, dim)
  if(any(dims[1,]!=dims[2,])) stop("Non-square matrices in X.\n")
  q <- rowSums(dims)[1]
  M <- matrix(0, q, q)
  # Determine allocation
  alloc <- split(1:q, 
                 do.call(c, lapply(1:K, function(i) rep(i, dims[1,i]))))
  # And allocate
  for(k in 1:K) M[alloc[[k]], alloc[[k]]] <- X[[k]]
  return(M)
}
