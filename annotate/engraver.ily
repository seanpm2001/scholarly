%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                                                             %
% This file is part of ScholarLY,                                             %
%                      =========                                              %
% a toolkit library for scholarly work with GNU LilyPond and LaTeX,           %
% belonging to openLilyLib (https://github.com/openlilylib/openlilylib        %
%              -----------                                                    %
%                                                                             %
% ScholarLY is free software: you can redistribute it and/or modify           %
% it under the terms of the GNU General Public License as published by        %
% the Free Software Foundation, either version 3 of the License, or           %
% (at your option) any later version.                                         %
%                                                                             %
% ScholarLY is distributed in the hope that it will be useful,                %
% but WITHOUT ANY WARRANTY; without even the implied warranty of              %
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               %
% GNU Lesser General Public License for more details.                         %
%                                                                             %
% You should have received a copy of the GNU General Public License           %
% along with ScholarLY.  If not, see <http://www.gnu.org/licenses/>.          %
%                                                                             %
% ScholarLY is maintained by Urs Liska, ul@openlilylib.org                    %
% Copyright Urs Liska, 2015                                                   %
%                                                                             %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%{
  This file defines the actual engraver
%}

%%%%%%%%%%
% Helpers:
%
% Predicate: an annotation is an alist that at least contains a number of
% default keys (which should usually be generated by the \annotate music function)
#(define (input-annotation? obj)
   (and
    (list? obj)
    (every pair? obj)
    (assq-ref obj 'message)
    (assq-ref obj 'type)
    (assq-ref obj 'location)))

% Create custom property 'annotation
% to pass information from the music function to the engraver
#(set-object-property! 'input-annotation 'backend-type? input-annotation?)
#(set-object-property! 'input-annotation 'backend-doc "custom grob property")



%%%%%%%%%%%%%%%%%%%%%
% Annotation engraver
% - Original stub provided by David Nalesnik
% - Adapted to the existing \annotation function by Urs Liska

% Collector acknowledges annotations and appends them
% to the global annotations object
annotationCollector =
#(lambda (context)
   (let* ((grobs '()))
     (make-engraver
      ;; receive grobs with annotations, set a few more properties
      ;; and append annotation objects to the global annotations list
      (acknowledgers
       ((grob-interface engraver grob source-engraver)
        (let ((annotation (ly:grob-property grob 'input-annotation)))
          ;; A grob is to be accepted when 'annotation *does* have some content
          (if (and (not (null-list? annotation))
                   ;; filter annotations the user has excluded
                   (not (member
                         (assq-ref annotation 'type)
                         (getOption '(scholarly annotate ignored-types)))))
              ;; add more properties that are only now available
              (begin
               (if (getOption '(scholarly colorize))
                   ;; colorize grob, retrieving color from sub-option
                   (set! (ly:grob-property grob 'color)
                         (getChildOption
                            '(scholarly annotate colors)
                            (assq-ref annotation 'type))))
               (if (or
                    (getOption '(scholarly annotate print))
                    (not (null? (getOption '(scholarly annotate export-targets)))))
                   ;; only add to the list of grobs in the engraver
                   ;; when we actually process them afterwards
                   (let ((ctx-id
                          ;; Set ctx-id to
                          ;; a) an explicit context name defined or
                          ;; b) an implicit context name through the named Staff context or
                          ;; c) the directory name (as determined in the \annotate function)
                          (or (assq-ref annotation 'context)
                              (let ((actual-context-id (ly:context-id context)))
                                (if (not (string=? actual-context-id "\\new"))
                                    actual-context-id
                                    #f))
                              (assq-ref annotation 'context-id))))
                     ;; Look up a context-name label from the options if one is set,
                     ;; otherwise use the retrieved context-name.
                     (set! annotation
                           (assq-set! annotation
                             'context-id
                             (getChildOptionWithFallback
                                '(scholarly annotate context-names)
                                (string->symbol ctx-id)
                                ctx-id)))
                     ;; Get the name of the annotated grob type
                     (set! annotation
                           (assq-set! annotation 'grob-type (grob::name grob)))
                     ;; Initialize a 'grob-location' property as a sub-alist,
                     ;; for now with a 'meter' property. This will be populated in 'finalize'.
                     (set! annotation
                           (assq-set! annotation 'grob-location
                             (assq-set! '() 'meter
                               (ly:context-property context 'timeSignatureFraction))))
                     (set! grobs (cons (list grob annotation) grobs)))))))))

      ;; Iterate over collected grobs and produce a list of annotations
      ;; (when annotations are neither printed nor logged the list is empty).
      ((finalize trans)
       (begin
        (for-each
         (lambda (g)
           (let* ((annotation (last g)))
             ;; Add location info, which seems only possible here
             (set! annotation (assq-set! annotation 'grob (first g)))

             ;; retrieve rhythmical properties of the grob and
             ;; store them in 'grob-location' alist
             (set! annotation
                   (assq-set! annotation 'grob-location
                     (grob-location-properties
                      (first g)
                      (assq-ref annotation 'grob-location))))

             ;; add current annotation to the list of annotations
             (set! annotations (append annotations (list annotation)))))
         (reverse grobs)))))))


% When the score is finalized this engraver
% processes the list of annotations and produces
% appropriate output.
annotationProcessor =
#(lambda (context)
   (make-engraver
    ((finalize trans)
     ;; Sort annotations by the given criteria
     (for-each
      (lambda (s)
        (set! annotations
              (sort-annotations annotations
                (assq-ref annotation-comparison-predicates s))))
      (reverse (getOption '(scholarly annotate sort-criteria))))

     ;; Optionally print annotations
     (if (getOption '(scholarly annotate print))
         (do-print-annotations))
     ;; Export iterating over all entries in the
     ;; annotation-export-targets configuration list
     (for-each
      (lambda (t)
        (let
         ((er (assq-ref (getOption '(scholarly annotate internal export-routines)) t)))
         ;; skip invalid entries
         (if er
             (er)
             (ly:warning (format "Invalid annotation export target: ~a" t)))))
      (getOption '(scholarly annotate export-targets))))))
