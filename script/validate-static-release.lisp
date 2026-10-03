(require :asdf)

(let* ((arguments (uiop:command-line-arguments))
       (source-root
         (and (first arguments)
              (uiop:ensure-directory-pathname (first arguments))))
       (library (uiop:getenv "ANTAIOS_FFF_LIBRARY"))
       (cache-root
         (merge-pathnames
          (format nil "antaios-static-smoke-~D/" (get-universal-time))
          (uiop:temporary-directory))))
  (labels ((fail (control &rest values)
             "Signal a static release smoke-test failure."
             (error "Static release smoke test failed: ~?" control values))

           (load-project ()
             "Load the locked Antaios system from SOURCE-ROOT."
             (let ((setup (merge-pathnames ".qlot/setup.lisp" source-root)))
               (unless (probe-file setup)
                 (fail "locked dependencies are absent."))
               (load setup)
               (asdf:load-asd (merge-pathnames "antaios.asd" source-root))
               (asdf:load-system :antaios))))
    (handler-case
        (progn
          (unless (and (= (length arguments) 1) source-root)
            (fail "usage: validate-static-release.lisp SOURCE"))
          (unless (and library (probe-file library))
            (fail "ANTAIOS_FFF_LIBRARY does not name the runtime."))
          (load-project)
          (unless (find ':number
                        (uiop:symbol-call
                         :colorlisp :highlight-spans
                         "fn main() { 42 }" :language ':rust)
                        :key (lambda (span)
                               (uiop:symbol-call
                                :colorlisp :span-category span)))
            (fail "ColorLisp did not classify a Rust number."))
          (uiop:ensure-all-directories-exist (list cache-root))
          (let ((engine
                  (uiop:symbol-call
                   :clifff :make-engine
                   :library-path (pathname library)
                   :base-path source-root
                   :cache-directory cache-root
                   :scan-timeout-milliseconds 30000)))
            (unwind-protect
                 (let ((result
                         (uiop:symbol-call
                          :clifff :engine-search-files
                          engine "antaios.asd" :page-size 1)))
                   (unless (find "antaios.asd" (getf result :items)
                                 :key (lambda (item) (getf item :path))
                                 :test #'string=)
                     (fail "FFF did not find antaios.asd.")))
              (uiop:symbol-call :clifff :engine-close engine)))
          (format t "~&Static native smoke test passed.~%"))
      (error (condition)
        (format *error-output* "~&~A~%" condition)
        (finish-output *error-output*)
        (uiop:quit 1))
      (:no-error (&rest values)
        (declare (ignore values))
        (uiop:delete-directory-tree cache-root
                                    :validate t
                                    :if-does-not-exist ':ignore)))))
