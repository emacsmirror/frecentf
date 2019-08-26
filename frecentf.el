;;; frecentf.el --- Pervasive recentf using frecency  -*- lexical-binding: t; -*-

;; Copyright © 2019  Felipe Lema

;; Author: Felipe Lema <felipel@mortemale.org>
;; Homepage: https://launchpad.net/frecentf.el
;; Keywords: files maint
;; Package-Requires: ((emacs "26") (frecency "0.1-pre") (persist "0.4"))
;; Version: 0.1

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

;; Slightly similar to `recentf', uses frecency for scoring entries.
;; Big differences with `recentf' are:
;; · simplified persistent list
;; · No entry is deleted when a buffer is killed (only when
;;   `frecentf-max-saved-items' is reached)

;;; Code:
(require 'cl-lib)
(require 'frecency)
(require 'persist)
(require 'seq)

;;; Variables
(persist-defvar frecentf-htable (make-hash-table :test 'equal)
		"A-list of frecently opened files.")
;;; custom
(defgroup frecentf nil
  "Maintain a menu of frecently opened files."
  :version "26.1"
  :group 'files)

(defcustom frecentf-max-saved-items 100
  "Maximum number of items of the frecent list that will be saved.
A nil value means to save the whole list."
  :group 'frecentf
  :type 'integer)

(defcustom frecentf-ignore-paths (list
				  (expand-file-name
				   (concat
				    user-emacs-directory
				    "persp-confs")))
  "List of path prefixes that will be ignored.

Be mindful that these paths will be tested by prefix, so if you have
/some/path, then /some/path/inside/very/deep/inside/file will be ignored.

See also `frecentf--add-entry'."
  :group 'frecentf
  :type '(repeat string))

(defcustom frecentf-also-store-dirname nil
  "When adding a file, will also add its dirname when this variable is non-nil."
  :group 'frecentf
  :type 'boolean)


;;; functions
(defun frecentf-track-opened-file ()
  "Insert the name of the file just opened or written into the recent list.

Based off `recentf-track-opened-file'"
  (when buffer-file-name
    (frecentf-add-path buffer-file-name))
  ;; Must return nil because it is run from `write-file-functions'.
  nil)
(defun frecentf-add-path (path)
  "Add PATH and its directory."
  (if (and frecentf-also-store-dirname
	   (file-directory-p path))
      (frecentf--add-directory path) ;; add path-as-directory
    ;; else, add the file path and its directory
    (frecentf--add-file path)
    (frecentf--add-directory (file-name-directory path))))

(defun frecentf--add-file (file-path)
  "Add FILE-PATH or update its timestamps if it's already been added."
  (frecentf--add-entry file-path 'file))

(defun frecentf--add-directory (dir-path)
  "Add DIR-PATH or update its timestamps if it's already been added."
  (frecentf--add-entry dir-path 'dir))

(defun frecentf--add-entry (path type-of-path)
  "Add a PATH to `frecentf-htable' with an associated TYPE-OF-PATH.

TYPE-OF-PATH ∈ '(file dir).

If PATH is prefixed by any of `frecentf-ignore-paths', it won't be added."
  (cl-assert (symbolp type-of-path))
  (cl-assert (cl-find type-of-path '(file dir)))
  ;; don't add if entry is within any to-be-filtered
  (unless (seq-find (lambda (prefix)
		      (string-prefix-p prefix path))
		    frecentf-ignore-paths)
    (let* ((original-entry (gethash path frecentf-htable
				    (a-list :type type-of-path)))
	   (updated-entry (frecency-update
			   original-entry)))
      ;; ensure path has its type updated in the very rare cases it's changed
      (setf (alist-get :type updated-entry)
	    type-of-path)
      (puthash path updated-entry frecentf-htable))
    ;; entry added, ensure post-condition
    (frecentf--ensure-max-cap)))

(defun frecentf--table-as-list ()
  "Return `frecentf-htable' as list."
  (let (collected)
    (maphash
     (lambda (key frecency-struct)
       (push (list key frecency-struct)
	     collected))
     frecentf-htable)
    collected))

(defun frecentf--table-as-sorted-list ()
  "Return `frecentf-htable' as list."

  (frecency-sort
   (frecentf--table-as-list)
   :get-fn (lambda (p_fr key)
	     (cl-multiple-value-bind (path frecency-struct) p_fr
	       (ignore path)
	       (a-get frecency-struct key)))))

(defun frecentf--ensure-max-cap ()
  "Ensure `frecentf-htable' has at most `frecentf-max-saved-items'.

Only the entries with the highest score survive."
  (let* ((sorted-by-score (frecentf--table-as-sorted-list))
	 ;; construct a new table…
	 (new-table (make-hash-table :test 'equal)))
    ;; …with only the first elements…
    (cl-loop for (path frecency-struct) in (seq-take sorted-by-score
						     frecentf-max-saved-items)
	     do (puthash path frecency-struct new-table))
    ;; …and assign it
    (setq frecentf-htable
	  new-table)))

(defun frecentf--pick-by (type action)
  "Pick a path that is of TYPE and call ACTION on it."
  (let* ((ivy-sort-functions-alist nil)
	 (all-sorted (frecentf--table-as-sorted-list))
	 (file-paths (seq-filter
		      (lambda (p_fr)
			(cl-multiple-value-bind (path frecency-struct) p_fr
			  (ignore path)
			  (eq (alist-get :type frecency-struct)
			      type)))
		      all-sorted)))
    (ignore ivy-sort-functions-alist)
    (if (not file-paths)
	(throw 'no-files)
      (if-let ((picked-file
		(completing-read "frecent files: "
				 (lambda (string pred action)
				   (pcase action
				     ('metadata
				      `(metadata
					(display-sort-function . identity)
					(cycle-sort-function . identity)))
				     (_
				      (complete-with-action action
							    file-paths
							    string
							    pred))))
				 nil
				 t)))
	  (funcall action picked-file)
	(throw 'no-pick)))))

;;; hooks
(add-hook 'find-file-hook #'frecentf-track-opened-file)
(add-hook 'write-file-functions #'frecentf-track-opened-file)

;;; official API

;;;###autoload
(defun frecentf-pick-file (action)
  "Pick a file and call ACTION on it.

When called interactively, call `find-file'"
  (interactive
   (list 'find-file))
  (condition-case nil
      (frecentf--pick-by 'file action)
    (no-files
     (message "no saved files"))
    (no-pick
     (message "no file picked"))))

;;;###autoload
(defun frecentf-pick-dir (action)
  "Pick a file and call ACTION on it.

When called interactively, call `dired'"
  (interactive
   (list 'dired))
  (condition-case nil
      (frecentf--pick-by 'dir action)
    (no-files
     (message "no saved directories"))
    (no-pick
     (message "no directory picked"))))

(provide 'frecentf)
;;; frecentf.el ends here
