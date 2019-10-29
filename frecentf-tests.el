;;; frecentf-tests.el --- smoke tests for frecentf              -*- lexical-binding: t; -*-

;; Copyright © 2019  Felipe Lema

;; Author: Felipe Lema <felipelema@mortemale.org>
;; Keywords:

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU Lesser General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU Lesser General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; this is a smoke test script that's meant to be run in the command line.  It
;; checks that nothing is broken.

;;; Code:

(unless noninteractive
  (error (concat
	  "Do not run these tests in non-batch mode: "
	  "there are some variable settings that may break your running "
	  "Emacs instance")))

;;;; load pre-requisites
;;;;; straight
;; https://github.com/raxod502/straight.el
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 4))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
	(url-retrieve-synchronously
	 "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
	 'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage)
  (ignore bootstrap-version))
(require 'straight)
;;;;; packages
(straight-use-package 'buttercup)
(straight-use-package 'frecency)
(straight-use-package 'persist)
;;;;; frecentf code
(load-file "./frecentf.el")

;;; tests themselves
(require 'buttercup)
(require 'frecentf)


(defvar testing--previous-persist--directory-location
  nil)
(defconst testing--persist--directory-location
  (make-temp-file
   "frecentf-test-persist"
   t))

(describe "use"
	  (before-each
	   (setq testing--persist--directory-location
		 persist--directory-location)
	   (setq
	    persist--directory-location
	    (locate-user-emacs-file "test-persist")))
	  (after-each
	   (delete-directory testing--persist--directory-location t))
	  (it "turn on"
	      (frecentf-mode)
	      (let ((some-path testing--persist--directory-location))
		(frecentf--add-directory some-path)
		(let ((sorted-table (frecentf--table-as-sorted-list)))
		  (expect sorted-table :not :to-be nil)
		  (pcase (frecentf--table-as-sorted-list)
		    (`((,path . ,properties)) ;; signle-item alist
		     (expect path :to-equal some-path)
		     (expect (a-get properties :type) :to-equal 'dir)))))))


(provide 'frecentf-tests)
;;; frecentf-tests.el ends here
