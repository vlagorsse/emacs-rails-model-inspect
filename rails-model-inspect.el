;;; rails-model-inspect.el --- Inspect Rails model fields and associations -*- lexical-binding: t -*-

;; Author: Vincent
;; Version: 0.1.0
;; Keywords: rails, ruby
;; URL: https://github.com/vlagorsse/emacs-rails-model-inspect
;; Package-Requires: ((emacs "27.1"))

;;; Commentary:
;; Inspect a Rails model's fields, associations, validations and enums
;; directly from Emacs without leaving your editor.

;;; Code:

(defconst rails-model-inspect--script "
Rails.application.eager_load!
model = '%s'.constantize
puts \"== \#{model.name} ==\"
begin
  model.columns.each do |col|
    line = \"  %%-30s %%-20s\" %% [col.name, col.sql_type]
    line += ' NOT NULL'                unless col.null
    line += \" DEFAULT=\#{col.default}\" if col.default
    puts line
  end
rescue => e
  puts \"  (columns unavailable: \#{e.message})\"
end
assocs = model.reflect_on_all_associations
unless assocs.empty?
  puts \"  Associations:\"
  assocs.each { |a| puts \"    \#{a.macro} :\#{a.name}\" }
end
vals = model.validators
unless vals.empty?
  puts \"  Validations:\"
  vals.each do |v|
    attrs = v.respond_to?(:attributes) && v.attributes.any? ? \" on :\#{v.attributes.join(', ')}\" : \"\"
    puts \"    \#{v.class.name.demodulize}\#{attrs}\"
  end
end
if model.defined_enums.any?
  puts \"  Enums:\"
  model.defined_enums.each { |name, values| puts \"    \#{name}: \#{values.keys.join(', ')}\" }
end")

(defun rails-model-inspect--find-root ()
  "Find the Rails project root."
  (locate-dominating-file default-directory "Gemfile"))

(defun rails-model-inspect--model-names (root)
  "Return a sorted list of model names found in ROOT."
  (let ((files (directory-files-recursively
                (expand-file-name "app/models" root) "\\.rb$")))
    (sort (mapcar (lambda (f)
                    (mapconcat #'capitalize
                               (split-string (file-name-base f) "_")
                               ""))
                  files)
          #'string<)))

;;;###autoload
(defun rails-model-inspect ()
  "Inspect a Rails model's fields, associations, validations and enums."
  (interactive)
  (let ((root (rails-model-inspect--find-root)))
    (unless root
      (error "Not inside a Rails project"))
    (let* ((model (completing-read "Model: "
                                   (rails-model-inspect--model-names root)
                                   nil t))
           (buf (get-buffer-create (format "*Rails Model: %s*" model)))
           (tmpfile (make-temp-file "rails-model-" nil ".rb")))
      (write-region (format rails-model-inspect--script model) nil tmpfile)
      (with-current-buffer buf
        (read-only-mode -1)
        (erase-buffer)
        (insert (format "Loading %s...\n" model))
        (read-only-mode 1)
        (display-buffer buf))
      (let ((default-directory root))
        (make-process
         :name "rails-model-inspect"
         :buffer buf
         :filter (lambda (proc string)
                   (let ((clean (replace-regexp-in-string
                                 "\033\\[[0-9;]*[mK]" "" string)))
                     (with-current-buffer (process-buffer proc)
                       (read-only-mode -1)
                       (goto-char (point-max))
                       (insert clean)
                       (read-only-mode 1))))
         :sentinel (lambda (proc event)
                     (when (string-match "finished" event)
                       (with-current-buffer (process-buffer proc)
                         (read-only-mode -1)
                         (goto-char (point-min))
                         (flush-lines "VIPS\\|Rails\\|Sidekiq\\|Honeybadger\\|DEPRECATION\\|Watching\\|Loaded\\|Multipart\\|WARNING\\|DEBUG\\|json-schema\\|Loading")
                         (read-only-mode 1))
                       (delete-file tmpfile)))
         :command (list "bash" "-c"
                        (format "RAILS_LOG_LEVEL=fatal rails runner %s 2>/dev/null"
                                (shell-quote-argument tmpfile))))))))

(provide 'rails-model-inspect)
;;; rails-model-inspect.el ends here
