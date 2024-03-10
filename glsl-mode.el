;;; glsl-mode.el --- Major mode for Open GLSL shader files -*- lexical-binding: t -*-

;; Copyright (C) 1999, 2000, 2001 Free Software Foundation, Inc.
;; Copyright (C) 2011, 2014, 2019 Jim Hourihan
;; Copyright (C) 2024 Gustaf Waldemarson
;;
;; Authors: Gustaf Waldemarson <gustaf.waldemarson ~at~ gmail.com>
;;          Jim Hourihan <jimhourihan ~at~ gmail.com>
;;          Xavier.Decoret@imag.fr,
;; Keywords: languages OpenGL GPU SPIR-V Vulkan
;; Version: 3.0
;; URL: https://github.com/jimhourihan/glsl-mode
;; Package-Requires: ((emacs "26.1"))
;;
;; Original URL: http://artis.inrialpes.fr/~Xavier.Decoret/resources/glsl-mode/

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This file is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Major mode for editing OpenGLSL grammar files.  Is is based on c-mode plus
;; some features and pre-specified fontifications.
;;
;; Modifications from the 1.0 version of glsl-mode (jimhourihan):
;;  * Removed original optimized regexps for font-lock-keywords and
;;    replaced with keyword lists for easier maintenance
;;  * Added customization group and faces
;;  * Preprocessor faces
;;  * Updated to GLSL 4.6
;;  * Separate deprecated symbols
;;  * Made _ part of a word
;;  * man page lookup at opengl.org

;;; Code:

(require 'cc-mode)
(require 'align)
(require 'glsl-db)

(eval-when-compile
  (require 'cc-langs)
  (require 'cc-fonts)
  (require 'cl-lib)
  (require 'find-file))


(defgroup glsl nil
  "OpenGL Shading Language Major Mode."
  :group 'languages)

(defconst glsl-language-version "4.6"
  "GLSL language version number.")

(defconst glsl-version "4.6"
  "OpenGL major mode version number.")

(defvar glsl-mode-menu nil "Menu for GLSL mode.")

(defvar glsl-mode-hook nil "GLSL mode hook.")

(defvar glsl-extension-color "#A82848"
  "Color used for extension specifiers.")

(defvar glsl-extension-face 'glsl-extension-face)
(defface glsl-extension-face
  `((t (:foreground ,glsl-extension-color :weight bold)))
  "Custom face for GLSL extension."
  :group 'glsl)

(defvar glsl-shader-variable-name-face 'glsl-shader-variable-name-face)
(defface glsl-shader-variable-name-face
  '((t (:inherit font-lock-variable-name-face :weight bold)))
  "GLSL type face."
  :group 'glsl)

(defvar glsl-type-face 'glsl-type-face)
(defface glsl-type-face
  '((t (:inherit font-lock-type-face)))
  "GLSL type face."
  :group 'glsl)

(defvar glsl-builtin-face 'glsl-builtin-face)
(defface glsl-builtin-face
  '((t (:inherit font-lock-builtin-face)))
  "GLSL builtin face."
  :group 'glsl)

(defvar glsl-deprecated-builtin-face 'glsl-deprecated-builtin-face)
(defface glsl-deprecated-builtin-face
  '((t (:inherit font-lock-warning-face)))
  "GLSL deprecated builtins face."
  :group 'glsl)

(defvar glsl-qualifier-face 'glsl-qualifier-face)
(defface glsl-qualifier-face
  '((t (:inherit font-lock-keyword-face)))
  "GLSL qualifiers face."
  :group 'glsl)

(defvar glsl-keyword-face 'glsl-keyword-face)
(defface glsl-keyword-face
  '((t (:inherit font-lock-keyword-face)))
  "GLSL keyword face."
  :group 'glsl)

(defvar glsl-deprecated-keyword-face 'glsl-deprecated-keyword-face)
(defface glsl-deprecated-keyword-face
  '((t (:inherit font-lock-warning-face)))
  "GLSL deprecated keywords face."
  :group 'glsl)

(defvar glsl-variable-name-face 'glsl-variable-name-face)
(defface glsl-variable-name-face
  '((t (:inherit font-lock-variable-name-face)))
  "GLSL variable face."
  :group 'glsl)

(defvar glsl-deprecated-variable-name-face 'glsl-deprecated-variable-name-face)
(defface glsl-deprecated-variable-name-face
  '((t (:inherit font-lock-warning-face)))
  "GLSL deprecated variable face."
  :group 'glsl)

(defvar glsl-reserved-keyword-face 'glsl-reserved-keyword-face)
(defface glsl-reserved-keyword-face
  '((t (:inherit glsl-keyword-face)))
  "GLSL reserved keyword face."
  :group 'glsl)

(defvar glsl-preprocessor-face 'glsl-preprocessor-face)
(defface glsl-preprocessor-face
  '((t (:inherit font-lock-preprocessor-face)))
  "GLSL preprocessor face."
  :group 'glsl)

(defcustom glsl-additional-types nil
  "List of additional keywords to be considered types.

 These keywords are added to the `glsl-type-list' and are fontified
using the `glsl-type-face'.  Examples of existing types include
\"float\", \"vec4\", and \"int\"."
  :type '(repeat (string :tag "Type Name"))
  :group 'glsl)

(defcustom glsl-additional-qualifiers nil
  "List of additional keywords to be considered qualifiers.

 These are added to the `glsl-qualifier-list' and are fontified using
the `glsl-qualifier-face'.  Examples of existing qualifiers include
\"const\", \"in\", and \"out\"."
  :type '(repeat (string :tag "Qualifier Name"))
  :group 'glsl)

(defcustom glsl-additional-keywords nil
  "List of additional GLSL keywords.

 These are added to the `glsl-keyword-list' and are fontified using
the `glsl-keyword-face'.  Example existing keywords include
\"while\", \"if\", and \"return\"."
  :type '(repeat (string :tag "Keyword"))
  :group 'glsl)

(defcustom glsl-additional-built-ins nil
  "List of additional functions to be considered built-in.

These are added to the `glsl-builtin-list' and are fontified using
the `glsl-builtin-face'."
  :type '(repeat (string :tag "Keyword"))
  :group 'glsl)

(defvar glsl-mode-hook nil)

(defvar glsl-mode-map
  (let ((glsl-mode-map (make-sparse-keymap)))
    (define-key glsl-mode-map [S-iso-lefttab] 'ff-find-other-file)
    glsl-mode-map)
  "Keymap for GLSL major mode.")

(defcustom glsl-browse-url-function #'browse-url
  "Function used to display GLSL man pages.

E.g. the function used by calls to 'browse-url', eww, w3m, etc."
  :type 'function
  :group 'glsl)

(defcustom glsl-man-pages-base-url "http://www.opengl.org/sdk/docs/man/html/"
  "Location of GL man pages."
  :type 'string
  :group 'glsl)

;;;###autoload
(progn
  (add-to-list 'auto-mode-alist '("\\.vert\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.frag\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.geom\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.tesc\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.tese\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.mesh\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.task\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.comp\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.rgen\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.rint\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.rchit\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.rahit\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.rcall\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.rmiss\\'" . glsl-mode))
  (add-to-list 'auto-mode-alist '("\\.glsl\\'" . glsl-mode)))

(eval-and-compile
  (defun glsl-ppre (re)
    (regexp-opt re 'words)))

(defvar glsl--preprocessor-rx
  (format "^[ \t]*#[ \t]*%s" (regexp-opt glsl-preprocessor-directive-list 'words)))

(defvar glsl--type-rx (glsl-ppre glsl-type-list))
(defvar glsl--deprecated-keywords-rx (glsl-ppre glsl-deprecated-qualifier-list))
(defvar glsl--reserved-keywords-rx (glsl-ppre glsl-reserved-list))
(defvar glsl--keywords-rx (glsl-ppre glsl-keyword-list))
(defvar glsl--qualifier-rx (glsl-ppre glsl-qualifier-list))
(defvar glsl--preprocessor-builtin-rx (glsl-ppre glsl-preprocessor-builtin-list))
(defvar glsl--deprecated-builtin-rx (glsl-ppre glsl-deprecated-builtin-list))
(defvar glsl--builtin-rx (regexp-opt glsl-builtin-list 'symbols))
(defvar glsl--deprecated-variables-rx (glsl-ppre glsl-deprecated-variables-list))
(defvar glsl--variables-rx "gl_[A-Z][A-Za-z_]+")
(defvar glsl--extensions-rx "GL_[A-Z]+_[a-zA-Z][a-zA-Z_0-9]+")


(defvar glsl-font-lock-keywords-1
  (append
   (list
    (cons glsl--preprocessor-rx glsl-preprocessor-face)
    (cons glsl--type-rx glsl-type-face)
    (cons glsl--deprecated-keywords-rx glsl-deprecated-keyword-face)
    (cons glsl--reserved-keywords-rx glsl-reserved-keyword-face)
    (cons glsl--qualifier-rx glsl-qualifier-face)
    (cons glsl--keywords-rx glsl-keyword-face)
    (cons glsl--preprocessor-builtin-rx glsl-keyword-face)
    (cons glsl--deprecated-builtin-rx glsl-deprecated-builtin-face)
    (cons glsl--builtin-rx glsl-builtin-face)
    (cons glsl--deprecated-variables-rx glsl-deprecated-variable-name-face)
    (cons glsl--variables-rx glsl-variable-name-face)
    (cons glsl--extensions-rx glsl-extension-face)))
  "Highlighting expressions for GLSL mode.")


(defvar glsl-font-lock-keywords glsl-font-lock-keywords-1
  "Default highlighting expressions for GLSL mode.")

(defvar glsl-mode-syntax-table
  (let ((glsl-mode-syntax-table (make-syntax-table)))
    (modify-syntax-entry ?/ ". 124b" glsl-mode-syntax-table)
    (modify-syntax-entry ?* ". 23" glsl-mode-syntax-table)
    (modify-syntax-entry ?\n "> b" glsl-mode-syntax-table)
    (modify-syntax-entry ?_ "w" glsl-mode-syntax-table)
    glsl-mode-syntax-table)
  "Syntax table for glsl-mode.")

(defvar glsl-other-file-alist
  '(("\\.frag$" (".vert"))
    ("\\.vert$" (".frag")))
  "Alist of extensions to find given the current file's extension.")

(defun glsl-man-completion-list ()
  "Return list of all GLSL keywords."
  (append glsl-builtin-list glsl-deprecated-builtin-list))

(defun glsl-find-man-page (thing)
  "Collects and displays manual entry for GLSL built-in function THING."
  (interactive
   (let ((word (current-word nil t)))
     (list
      (completing-read
       (concat "OpenGL.org GLSL man page: (" word "): ")
       (glsl-man-completion-list)
       nil nil nil nil word))))
  (save-excursion
    (apply glsl-browse-url-function
           (list (concat glsl-man-pages-base-url thing ".xhtml")))))

(easy-menu-define glsl-menu glsl-mode-map
  "GLSL Menu."
    `("GLSL"
      ["Comment Out Region"     comment-region
       (c-fn-region-is-active-p)]
      ["Uncomment Region"       (comment-region (region-beginning)
						(region-end) '(4))
       (c-fn-region-is-active-p)]
      ["Indent Expression"      c-indent-exp
       (memq (char-after) '(?\( ?\[ ?\{))]
      ["Indent Line or Region"  c-indent-line-or-region t]
      ["Fill Comment Paragraph" c-fill-paragraph t]
      "----"
      ["Backward Statement"     c-beginning-of-statement t]
      ["Forward Statement"      c-end-of-statement t]
      "----"
      ["Up Conditional"         c-up-conditional t]
      ["Backward Conditional"   c-backward-conditional t]
      ["Forward Conditional"    c-forward-conditional t]
      "----"
      ["Backslashify"           c-backslash-region (c-fn-region-is-active-p)]
      "----"
      ["Find GLSL Man Page"  glsl-find-man-page t]))

;;;###autoload
(define-derived-mode glsl-mode prog-mode "GLSL"
  "Major mode for editing GLSL shader files.

\\{glsl-mode-map}"
  (c-initialize-cc-mode t)
  (setq abbrev-mode t)
  (c-init-language-vars-for 'c-mode)
  (c-common-init 'c-mode)
  (cc-imenu-init cc-imenu-c++-generic-expression)
  (set (make-local-variable 'font-lock-defaults) '(glsl-font-lock-keywords))
  (set (make-local-variable 'ff-other-file-alist) 'glsl-other-file-alist)
  (set (make-local-variable 'comment-start) "// ")
  (set (make-local-variable 'comment-end) "")
  (set (make-local-variable 'comment-padding) "")
  (add-to-list 'align-c++-modes 'glsl-mode)
  (c-run-mode-hooks 'c-mode-common-hook)
  (run-mode-hooks 'glsl-mode-hook)
  (let* ((rx-extra '((glsl-additional-types . glsl-type-face)
                     (glsl-additional-keywords . glsl-keyword-face)
                     (glsl-additional-qualifiers . glsl-qualifer-face)
                     (glsl-additional-built-ins . glsl-builtin-face)))
         (fl-extras (cl-loop for (key . value) in rx-extra when (eval key)
                             collect (cons (glsl-ppre (eval key)) value))))
    (font-lock-add-keywords nil fl-extras))
  :after-hook (progn (c-make-noise-macro-regexps)
		     (c-make-macro-with-semi-re)
		     (c-update-modeline)))


(provide 'glsl-mode)

;;; glsl-mode.el ends here
