# encoding: utf-8
# cython: cdivision=True
# cython: boundscheck=False
# cython: wraparound=False
#
# Author: Mathieu Blondel
# License: BSD

import numpy as np
cimport numpy as np

from libc.math cimport sqrt

from lightning.impl.dataset_fast cimport RowDataset


cdef double _pred(double* data,
                  int* indices,
                  int n_nz,
                  double* w):

    cdef int j, jj
    cdef double dot = 0

    for jj in xrange(n_nz):
        j = indices[jj]
        dot += w[j] * data[jj]

    return dot


cdef double _proj_elastic(double eta,
                          int t,
                          double g_sum,
                          double alpha1,
                          double alpha2,
                          double delta,
                          double s):

    cdef double eta_t = eta * t
    cdef double denom = (delta + s + eta_t * alpha2)
    cdef double wj_new1 = eta_t * (-g_sum / t - alpha1) / denom
    cdef double wj_new2 = eta_t * (-g_sum / t + alpha1) / denom

    if wj_new1 > 0:
        return wj_new1
    elif wj_new2 < 0:
        return wj_new2
    else:
        return 0


def _adagrad_fit(RowDataset X,
                 np.ndarray[double, ndim=1]y,
                 np.ndarray[double, ndim=1]coef,
                 np.ndarray[double, ndim=1]g_sum,
                 np.ndarray[double, ndim=1]g_norms,
                 double eta,
                 double delta,
                 double alpha1,
                 double alpha2,
                 int n_iter,
                 rng):

    cdef int n_samples = X.get_n_samples()
    cdef int n_features = X.get_n_features()

    # Variables
    cdef int it, t, ii, i, jj, j
    cdef double y_pred, tmp, scale
    cdef np.ndarray[int, ndim=1] sindices
    sindices = np.arange(n_samples, dtype=np.int32)

    # Data pointers.
    cdef double* data
    cdef int* indices
    cdef int n_nz

    # Pointers
    cdef double* w = <double*>coef.data

    t = 1
    for t in xrange(n_iter):
        rng.shuffle(sindices)

        for ii in xrange(n_samples):
            i = sindices[ii]

            # Retrieve row.
            X.get_row_ptr(i, &indices, &data, &n_nz)

            y_pred = _pred(data, indices, n_nz, w)

            if y_pred * y[i] > 1:
                scale = 0
            else:
                scale = -y[i]

            # Update g_sum and g_norms
            if scale != 0:
                for jj in xrange(n_nz):
                    j = indices[jj]
                    tmp = scale * data[jj]
                    g_sum[j] += tmp
                    g_norms[j] += tmp * tmp

            # Update w
            for jj in xrange(n_nz):
                j = indices[jj]
                w[j] = _proj_elastic(eta, t, g_sum[j], alpha1, alpha2, delta,
                                     sqrt(g_norms[j]))

            t += 1
