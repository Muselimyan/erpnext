// Name: Task-Photo-System
// DocType: Task
// Enabled: 1
// ---

// === LOGGING ===
console.log('[Photo] Task-Photo-System loaded at', new Date().toISOString());
window.PHOTO_DEBUG = true;
window._photoLog = function(tag, msg, data) {
    if (!window.PHOTO_DEBUG) return;
    var prefix = '[Photo][' + tag + ']';
    if (data !== undefined) { console.log(prefix, msg, data); }
    else { console.log(prefix, msg); }
};
window._photoWarn = function(tag, msg, data) {
    if (!window.PHOTO_DEBUG) return;
    var prefix = '[Photo][' + tag + ']';
    if (data !== undefined) { console.warn(prefix, msg, data); }
    else { console.warn(prefix, msg); }
};
window._photoErr = function(tag, msg, data) {
    var prefix = '[Photo][' + tag + ']';
    if (data !== undefined) { console.error(prefix, msg, data); }
    else { console.error(prefix, msg); }
};

// =============================================================================
// PhotoFullscreen — reusable fullscreen image viewer
// =============================================================================
window.PhotoFullscreen = {
    open: function(url, title) {
        if (!url) return;
        title = title || 'Photo';
        $('#photo-fullscreen-overlay').remove();
        var scale = 1, minScale = 0.5, maxScale = 6, x = 0, y = 0;
        var pointers = {}, dragStart = null, pinchStart = null;

        var overlay = $('<div id="photo-fullscreen-overlay" style="position:fixed;z-index:99999;left:0;top:0;width:100vw;height:100vh;background:rgba(0,0,0,0.94);display:flex;flex-direction:column;box-sizing:border-box;overflow:hidden;"></div>');
        var toolbar = $('<div style="flex:0 0 auto;display:flex;align-items:center;gap:8px;padding:10px;background:rgba(0,0,0,0.75);color:#fff;box-sizing:border-box;z-index:2;"></div>');
        var caption = $('<div style="flex:1;min-width:0;font-size:12px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;"></div>').text(title);
        var zoomOut = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 11px;font-weight:bold;">\u2212</button>');
        var zoomIn = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 11px;font-weight:bold;">+</button>');
        var resetBtn = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 10px;font-weight:bold;">Reset</button>');
        var closeBtn = $('<button type="button" style="background:#fff;color:#111;border:0;border-radius:6px;padding:8px 12px;font-weight:bold;">Close</button>');
        var viewport = $('<div style="position:relative;flex:1 1 auto;overflow:hidden;touch-action:none;cursor:grab;background:#111;"></div>');
        var img = $('<img />').attr('src', url).attr('alt', title).css({position:'absolute', left:'50%', top:'50%', maxWidth:'96%', maxHeight:'96%', transformOrigin:'center center', userSelect:'none', webkitUserSelect:'none', touchAction:'none', borderRadius:'6px'});

        function clampScale(v) { return Math.max(minScale, Math.min(maxScale, v)); }
        function clampPan() {
            var rect = viewport[0].getBoundingClientRect();
            var baseW = img[0].clientWidth || rect.width;
            var baseH = img[0].clientHeight || rect.height;
            var visibleEdge = 80;
            var maxX = Math.max(visibleEdge, (baseW * scale + rect.width) / 2 - visibleEdge);
            var maxY = Math.max(visibleEdge, (baseH * scale + rect.height) / 2 - visibleEdge);
            x = Math.max(-maxX, Math.min(maxX, x));
            y = Math.max(-maxY, Math.min(maxY, y));
        }
        function applyTransform() { clampPan(); img.css('transform', 'translate(calc(-50% + ' + x + 'px), calc(-50% + ' + y + 'px)) scale(' + scale + ')'); }
        function zoomAt(newScale, cx, cy) {
            newScale = clampScale(newScale);
            var rect = viewport[0].getBoundingClientRect();
            var dx = cx - (rect.left + rect.width / 2) - x;
            var dy = cy - (rect.top + rect.height / 2) - y;
            var factor = newScale / scale;
            x -= dx * (factor - 1);
            y -= dy * (factor - 1);
            scale = newScale;
            applyTransform();
        }
        function pointDistance(a, b) { var dx = a.clientX - b.clientX, dy = a.clientY - b.clientY; return Math.sqrt(dx * dx + dy * dy); }
        function pointMid(a, b) { return { clientX: (a.clientX + b.clientX) / 2, clientY: (a.clientY + b.clientY) / 2 }; }

        zoomOut.on('click', function(e) { e.preventDefault(); e.stopPropagation(); var r = viewport[0].getBoundingClientRect(); zoomAt(scale - 0.25, r.left + r.width / 2, r.top + r.height / 2); return false; });
        zoomIn.on('click', function(e) { e.preventDefault(); e.stopPropagation(); var r = viewport[0].getBoundingClientRect(); zoomAt(scale + 0.25, r.left + r.width / 2, r.top + r.height / 2); return false; });
        resetBtn.on('click', function(e) { e.preventDefault(); e.stopPropagation(); scale = 1; x = 0; y = 0; applyTransform(); return false; });
        closeBtn.on('click', function(e) { e.preventDefault(); e.stopPropagation(); overlay.remove(); return false; });

        viewport.on('wheel', function(e) { e.preventDefault(); var oe = e.originalEvent; zoomAt(scale * (oe.deltaY < 0 ? 1.12 : 0.88), oe.clientX, oe.clientY); return false; });
        viewport.on('pointerdown', function(e) {
            e.preventDefault(); viewport[0].setPointerCapture(e.originalEvent.pointerId); pointers[e.originalEvent.pointerId] = e.originalEvent;
            var ids = Object.keys(pointers);
            if (ids.length === 1) { dragStart = { clientX: e.originalEvent.clientX, clientY: e.originalEvent.clientY, x: x, y: y }; viewport.css('cursor', 'grabbing'); }
            if (ids.length === 2) { var p1 = pointers[ids[0]], p2 = pointers[ids[1]]; pinchStart = { dist: pointDistance(p1, p2), scale: scale, x: x, y: y, mid: pointMid(p1, p2) }; }
            return false;
        });
        viewport.on('pointermove', function(e) {
            if (!pointers[e.originalEvent.pointerId]) return false;
            pointers[e.originalEvent.pointerId] = e.originalEvent;
            var ids = Object.keys(pointers);
            if (ids.length >= 2 && pinchStart) {
                var p1 = pointers[ids[0]], p2 = pointers[ids[1]], mid = pointMid(p1, p2);
                x = pinchStart.x + (mid.clientX - pinchStart.mid.clientX);
                y = pinchStart.y + (mid.clientY - pinchStart.mid.clientY);
                scale = clampScale(pinchStart.scale * (pointDistance(p1, p2) / pinchStart.dist));
                applyTransform();
            } else if (ids.length === 1 && dragStart) {
                x = dragStart.x + (e.originalEvent.clientX - dragStart.clientX);
                y = dragStart.y + (e.originalEvent.clientY - dragStart.clientY);
                applyTransform();
            }
            return false;
        });
        viewport.on('pointerup pointercancel pointerleave', function(e) {
            delete pointers[e.originalEvent.pointerId];
            viewport.css('cursor', 'grab');
            dragStart = null;
            pinchStart = null;
            var ids = Object.keys(pointers);
            if (ids.length === 1) { var p = pointers[ids[0]]; dragStart = { clientX: p.clientX, clientY: p.clientY, x: x, y: y }; }
            return false;
        });

        // Escape key
        $(document).on('keydown.photoFullscreen', function(e) {
            if (e.key === 'Escape' || e.keyCode === 27) { overlay.remove(); $(document).off('keydown.photoFullscreen'); }
        });
        overlay.on('remove', function() { $(document).off('keydown.photoFullscreen'); });

        toolbar.append(caption).append(zoomOut).append(zoomIn).append(resetBtn).append(closeBtn);
        viewport.append(img);
        overlay.append(toolbar).append(viewport);
        $('body').append(overlay);
        applyTransform();
    }
};

// =============================================================================
// PhotoGallery — standalone photo gallery widget
// Input: [{url, filename}]  Output: getPhotos() -> [{url, filename}]
// Knows nothing about documents, doctypes, or business logic.
// =============================================================================
window.PhotoGallery = function(opts) {
    this._container = opts.container;
    this._mode = opts.mode || 'editable';
    this._photos = (opts.photos || []).map(function(p) { return {url: p.url, filename: p.filename}; });
    this._maxPhotos = opts.maxPhotos || 5;
    this._label = opts.label || 'Photos';
    this._addButtonLabel = opts.addButtonLabel || '+ Add Photos';
    this._thumbnailSize = opts.thumbnailSize || {w: 76, h: 76};
    this._onChange = opts.onChange || null;
    this._onUpload = opts.onUpload || null; // called with {url, filename} after each successful upload
    this._destroyed = false;
    this._render();
};

window.PhotoGallery.prototype.getPhotos = function() {
    return this._photos.map(function(p) { return {url: p.url, filename: p.filename}; });
};

window.PhotoGallery.prototype.setMode = function(mode) {
    this._mode = mode;
    this._render();
};

window.PhotoGallery.prototype.refresh = function(photos) {
    this._photos = (photos || []).map(function(p) { return {url: p.url, filename: p.filename}; });
    this._render();
};

window.PhotoGallery.prototype.destroy = function() {
    this._destroyed = true;
    if (this._container) { $(this._container).empty(); }
    this._container = null;
    this._photos = [];
};

window.PhotoGallery.prototype._render = function() {
    if (this._destroyed || !this._container) return;
    var self = this;
    var $c = $(this._container);
    $c.empty();

    var isEditable = this._mode === 'editable';
    var count = this._photos.length;

    // Empty + readonly: render nothing
    if (!count && !isEditable) return;

    // Label — matches Frappe's native .control-label style
    var $label = $('<div class="control-label" style="margin-bottom:8px;"></div>').text(this._label);
    $c.append($label);

    // Flex row: thumbnails + add button inline
    var $gallery = $('<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center;"></div>');

    // Thumbnails
    this._photos.forEach(function(photo, idx) {
        var safeUrl = frappe.utils.escape_html(photo.url || '');
        var safeTitle = frappe.utils.escape_html(photo.filename || 'Photo');
        var tw = self._thumbnailSize.w;
        var th = self._thumbnailSize.h;

        var $wrap = $('<div style="position:relative;display:inline-block;"></div>');

        // Thumbnail button -> fullscreen
        var $thumb = $('<button type="button" style="display:block;padding:0;border:0;background:transparent;line-height:0;cursor:pointer;"></button>');
        var $img = $('<img />').attr('src', safeUrl).attr('title', safeTitle).css({width: tw + 'px', height: th + 'px', objectFit: 'cover', border: '1px solid #d1d8dd', borderRadius: '6px', background: '#f8f9fa'});
        $img.on('error', function() { console.warn('[Photo] image load error:', photo.url); });
        $thumb.append($img);
        $thumb.on('click', function(e) { e.preventDefault(); e.stopPropagation(); window.PhotoFullscreen.open(photo.url, photo.filename); return false; });
        $wrap.append($thumb);

        // Delete button (editable only)
        if (isEditable) {
            var $del = $('<button type="button" style="position:absolute;top:-4px;right:-4px;width:20px;height:20px;border-radius:50%;border:none;background:#e74c3c;color:#fff;font-size:12px;line-height:20px;text-align:center;padding:0;cursor:pointer;z-index:1;">x</button>');
            $del.on('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                if (!confirm('Remove this photo?')) return;
                self._photos.splice(idx, 1);
                window._photoLog && window._photoLog('gallery', 'removed photo idx=' + idx + ' url=' + photo.url);
                self._onChange && self._onChange();
                self._render();
            });
            $wrap.append($del);
        }

        $gallery.append($wrap);
    });

    // Add button inline (editable + below max)
    if (isEditable) {
        var canAdd = count < this._maxPhotos;
        var $btn = $('<button type="button" class="btn btn-sm btn-primary photo-gallery-add-btn" style="font-size:12px;padding:6px 16px;background:#000;border-color:#000;color:#fff;border-radius:7px;' + (canAdd ? '' : 'opacity:0.5;cursor:not-allowed;') + '">' + frappe.utils.escape_html(this._addButtonLabel) + '</button>');
        $btn.on('click', function() {
            if (!canAdd) {
                frappe.msgprint(__('Maximum ' + self._maxPhotos + ' photos.'));
                return;
            }
            self._openFilePicker();
        });
        $gallery.append($btn);
    }

    $c.append($gallery);
};

window.PhotoGallery.prototype._openFilePicker = function() {
    var self = this;
    var remaining = this._maxPhotos - this._photos.length;
    if (remaining <= 0) {
        frappe.msgprint(__('Maximum ' + this._maxPhotos + ' photos.'));
        return;
    }

    var $input = $('<input type="file" accept="image/*" multiple style="display:none;" />');
    $input.on('change', function() {
        var files = Array.prototype.slice.call(this.files || []);
        if (!files.length) return;
        // Limit to remaining slots
        if (files.length > remaining) {
            frappe.msgprint(__('You can add up to ' + remaining + ' more photo(s). Only the first ' + remaining + ' will be uploaded.'));
            files = files.slice(0, remaining);
        }
        window._photoLog && window._photoLog('gallery', 'uploading ' + files.length + ' file(s)...');
        files.forEach(function(file) {
            self._uploadFile(file);
        });
        $input.remove();
    });
    $('body').append($input);
    $input[0].click();
};

window.PhotoGallery.prototype._uploadFile = function(file) {
    var self = this;
    var formData = new FormData();
    formData.append('file', file, file.name);
    formData.append('is_private', '1');
    formData.append('folder', 'Home/Attachments');

    fetch('/api/method/upload_file', {
        method: 'POST',
        headers: { 'X-Frappe-CSRF-Token': frappe.csrf_token },
        body: formData
    })
    .then(function(r) { return r.json(); })
    .then(function(data) {
        if (data.message && data.message.file_url) {
            var photo = { url: data.message.file_url, filename: data.message.file_name || file.name, file_record: data.message.name || null };
            self._photos.push(photo);
            window._photoLog && window._photoLog('gallery', 'uploaded: url=' + photo.url + ' filename=' + photo.filename + ' file_record=' + photo.file_record);
            self._onUpload && self._onUpload(photo);
            self._onChange && self._onChange();
            self._render();
        } else {
            window._photoWarn && window._photoWarn('gallery', 'upload response missing file_url', data);
        }
    })
    .catch(function(err) {
        window._photoErr && window._photoErr('gallery', 'upload failed for ' + file.name, err);
    });
};


// =============================================================================
// Task Form Handlers — the ONLY code that knows about Tasks
// =============================================================================

(function() {
    var IMAGE_RE = /\.(jpe?g|png|gif|webp|heic|heif)$/i;

    function isImage(url) { return IMAGE_RE.test(url || ''); }

    function getTaskPhotoConfig(frm) {
        var kind = (frm.doc.task_kind || '').trim();
        switch (kind) {
            case 'Pack / prepare items':
                return { key: 'pack', editable: true, label: 'Warehouse Pickup Photos', sourceTask: frm.doc.name };
            case 'Pickup Returns':
                return { key: 'pickup_returns', editable: true, label: 'Warehouse Drop-off Photos', sourceTask: frm.doc.name };
            case 'Returns processing / verification':
                return { key: 'inspect', editable: false, label: 'Pack / Prepare Photos', sourceTask: null, needsPackLookup: true };
            case 'Other: Entry':
            case 'Other: Processing':
                return { key: 'other', editable: true, label: 'Task Photos', sourceTask: frm.doc.name };
            default:
                return null;
        }
    }

    function fetchImageFiles(taskName, callback) {
        window._photoLog && window._photoLog('form', 'fetchImageFiles: querying attached images for task=' + taskName);
        frappe.call({
            method: 'frappe.client.get_list',
            args: {
                doctype: 'File',
                filters: { attached_to_doctype: 'Task', attached_to_name: taskName },
                fields: ['name', 'file_url', 'file_name'],
                order_by: 'creation asc',
                limit_page_length: 50
            },
            callback: function(r) {
                var allFiles = r.message || [];
                var files = allFiles.filter(function(f) { return isImage(f.file_url); });
                var seen = {};
                var unique = [];
                files.forEach(function(f) {
                    if (!f.file_url || seen[f.file_url]) return;
                    seen[f.file_url] = true;
                    unique.push({ url: f.file_url, filename: f.file_name || '' });
                });
                window._photoLog && window._photoLog('form', 'fetchImageFiles: task=' + taskName + ' total_files=' + allFiles.length + ' images=' + files.length + ' unique=' + unique.length + ' urls=' + JSON.stringify(unique.map(function(u){return u.url;})));
                callback(unique);
            },
            error: function(err) {
                window._photoErr && window._photoErr('form', 'fetchImageFiles error for task=' + taskName, err);
                callback([]);
            }
        });
    }

    function lookupPackTask(dispatchCase, callback) {
        if (!dispatchCase) { callback(null); return; }
        frappe.call({
            method: 'frappe.client.get_list',
            args: {
                doctype: 'Task',
                filters: { dispatch_case: dispatchCase, task_kind: 'Pack / prepare items' },
                fields: ['name'],
                limit_page_length: 1
            },
            callback: function(r) {
                callback(r.message && r.message.length ? r.message[0].name : null);
            },
            error: function() { callback(null); }
        });
    }

    function getGalleryContainer(frm, key) {
        var $existing = $(frm.wrapper).find('#photo-gallery-host-' + key);
        if ($existing.length) return $existing[0];
        var $host = $('<div id="photo-gallery-host-' + key + '" style="margin-top:12px;margin-bottom:12px;"></div>');
        // Insert after dispatch_case field if available, otherwise after status
        var anchor = frm.fields_dict.dispatch_case || frm.fields_dict.status;
        if (anchor && anchor.$wrapper) {
            anchor.$wrapper.after($host);
        } else {
            $(frm.wrapper).find('.form-layout').first().append($host);
        }
        return $host[0];
    }

    function createOrRefreshGallery(frm, config, photos, mode) {
        frm._photoGalleries = frm._photoGalleries || {};
        frm._initialPhotos = frm._initialPhotos || {};
        frm._initialPhotos[config.key] = photos.map(function(p) { return {url: p.url, filename: p.filename}; });

        if (frm._photoGalleries[config.key]) {
            frm._photoGalleries[config.key].setMode(mode);
            frm._photoGalleries[config.key].refresh(photos);
        } else {
            var container = getGalleryContainer(frm, config.key);
            frm._photoGalleries[config.key] = new window.PhotoGallery({
                container: container,
                mode: mode,
                photos: photos,
                maxPhotos: 5,
                label: config.label,
                onChange: function() { frm.dirty(); },
                onUpload: function(photo) {
                    // Immediately attach the uploaded file to this Task
                    if (!photo.file_record) {
                        window._photoWarn && window._photoWarn('form', 'onUpload: no file_record name, cannot attach');
                        return;
                    }
                    window._photoLog && window._photoLog('form', 'onUpload: attaching file ' + photo.file_record + ' to Task/' + frm.doc.name);
                    frappe.call({
                        method: 'frappe.client.set_value',
                        args: {
                            doctype: 'File',
                            name: photo.file_record,
                            fieldname: JSON.stringify({
                                attached_to_doctype: 'Task',
                                attached_to_name: frm.doc.name
                            })
                        },
                        callback: function() {
                            window._photoLog && window._photoLog('form', 'onUpload: attach DONE file=' + photo.file_record + ' -> Task/' + frm.doc.name);
                        },
                        error: function(err) {
                            window._photoErr && window._photoErr('form', 'onUpload: attach FAILED file=' + photo.file_record, err);
                        }
                    });
                }
            });
        }
        window._photoLog && window._photoLog('form', 'gallery "' + config.key + '" ready: mode=' + mode + ' photos=' + photos.length);
    }

    frappe.ui.form.on('Task', {
        refresh: function(frm) {
            window._photoLog && window._photoLog('form', 'refresh: task=' + (frm.doc.name || 'NEW') + ' kind="' + (frm.doc.task_kind || '') + '" status="' + (frm.doc.status || '') + '"');



            var config = getTaskPhotoConfig(frm);

            // Destroy stale galleries
            Object.keys(frm._photoGalleries || {}).forEach(function(k) {
                if (!config || config.key !== k) {
                    frm._photoGalleries[k].destroy();
                    delete frm._photoGalleries[k];
                    delete (frm._initialPhotos || {})[k];
                }
            });

            if (!config) {
                window._photoLog && window._photoLog('form', 'no gallery config for kind="' + (frm.doc.task_kind || '') + '" — skipping');
                return;
            }
            if (frm.is_new()) {
                window._photoLog && window._photoLog('form', 'task is new — gallery deferred');
                return;
            }

            // Compute mode
            var roles = frappe.user_roles || [];
            var isAdmin = roles.indexOf('System Manager') !== -1 || roles.indexOf('Administrator') !== -1 || frappe.session.user === 'Administrator';
            var canEdit = isAdmin || (frm.doc.custom_accepted_by && frm.doc.custom_accepted_by === frappe.session.user);
            var mode = config.editable && canEdit ? 'editable' : 'readonly';
            window._photoLog && window._photoLog('form', 'config: key=' + config.key + ' mode=' + mode + ' (editable=' + config.editable + ' canEdit=' + canEdit + ' isAdmin=' + isAdmin + ' accepted_by="' + (frm.doc.custom_accepted_by || '') + '")');

            // Fetch photos and create gallery
            if (config.needsPackLookup) {
                lookupPackTask(frm.doc.dispatch_case, function(packTaskName) {
                    if (!packTaskName) {
                        window._photoWarn && window._photoWarn('form', 'Returns Inspection: no Pack task found for DC=' + frm.doc.dispatch_case);
                        createOrRefreshGallery(frm, config, [], 'readonly');
                        return;
                    }
                    fetchImageFiles(packTaskName, function(photos) {
                        createOrRefreshGallery(frm, config, photos, 'readonly');
                    });
                });
            } else {
                fetchImageFiles(config.sourceTask, function(photos) {
                    createOrRefreshGallery(frm, config, photos, mode);
                });
            }
        },

        after_save: function(frm) {
            var galleries = frm._photoGalleries || {};
            var initialPhotos = frm._initialPhotos || {};

            Object.keys(galleries).forEach(function(key) {
                var gallery = galleries[key];
                var config = getTaskPhotoConfig(frm);
                if (!config || !config.editable) return;

                var initial = initialPhotos[key] || [];
                var current = gallery.getPhotos();
                var initialUrls = initial.map(function(p) { return p.url; });
                var currentUrls = current.map(function(p) { return p.url; });

                // Files are attached immediately on upload (via onUpload callback).
                // after_save only handles deletion of removed photos.
                var removed = initialUrls.filter(function(u) { return currentUrls.indexOf(u) === -1; });

                window._photoLog && window._photoLog('form', 'after_save gallery="' + key + '": removed=' + removed.length);

                // Delete removed files
                removed.forEach(function(url) {
                    frappe.call({
                        method: 'frappe.client.get_list',
                        args: {
                            doctype: 'File',
                            filters: { file_url: url, attached_to_doctype: 'Task', attached_to_name: frm.doc.name },
                            fields: ['name'],
                            limit_page_length: 1
                        },
                        callback: function(r) {
                            var file = (r.message || [])[0];
                            if (file) {
                                window._photoLog && window._photoLog('form', 'deleting removed file ' + file.name + ' url=' + url);
                                frappe.call({
                                    method: 'frappe.client.delete',
                                    args: { doctype: 'File', name: file.name },
                                    callback: function() {
                                        window._photoLog && window._photoLog('form', 'delete DONE: file=' + file.name);
                                    },
                                    error: function() {
                                        window._photoWarn && window._photoWarn('form', 'delete failed, retrying: file=' + file.name);
                                        setTimeout(function() {
                                            frappe.call({
                                                method: 'frappe.client.delete',
                                                args: { doctype: 'File', name: file.name },
                                                error: function() { window._photoErr && window._photoErr('form', 'delete retry FAILED: file=' + file.name + ' url=' + url); }
                                            });
                                        }, 500);
                                    }
                                });
                            } else {
                                window._photoWarn && window._photoWarn('form', 'after_save: no File record found for removed url=' + url + ' on task=' + frm.doc.name + ' (nothing to delete)');
                            }
                        }
                    });
                });

                // Update initial for next save cycle
                frm._initialPhotos[key] = current;
            });
        }
    });
})();
