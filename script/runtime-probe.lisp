;;;; Shared host-runtime probe for launchers that have not loaded Antaios.

(require :asdf)
(load (merge-pathnames "runtime-requirement.lisp"
                       (uiop:pathname-directory-pathname *load-truename*)))

(let ((source-root (uiop:pathname-parent-directory-pathname
                    (uiop:pathname-directory-pathname *load-truename*))))
  (antaios-require-minimum-runtime (merge-pathnames "sbcl.version" source-root))
  (write-string (lisp-implementation-version)))
