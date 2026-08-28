// Name: Dispatch Case-Photo-Galleries
// DocType: Dispatch Case
// Enabled: 1
// ---

// Read-only photo galleries on the Dispatch Case form.
// Shows Pack task photos as "Warehouse Pickup Photos" and
// Pickup Returns task photos as "Warehouse Drop-off Photos".
// Uses live File record lookup from linked tasks (no stored URLs).

(function() {
    var IMAGE_RE = /\.(jpe?g|png|gif|webp|heic|heif)$/i;

    function fetchTaskImages(taskName, callback) {
        if (!taskName) { callback([]); return; }
        frappe.call({
            method: 'frappe.client.get_list',
            args: {
                doctype: 'File',
                filters: { attached_to_doctype: 'Task', attached_to_name: taskName },
                fields: ['file_url', 'file_name'],
                limit_page_length: 50
            },
            async: true,
            callback: function(r) {
                var files = (r && r.message) || [];
                var images = [];
                var seen = {};
                files.forEach(function(f) {
                    if (f.file_url && IMAGE_RE.test(f.file_url) && !seen[f.file_url]) {
                        seen[f.file_url] = true;
                        images.push({ url: f.file_url, filename: f.file_name || f.file_url.split('/').pop() });
                    }
                });
                callback(images);
            }
        });
    }

    function renderReadonlyGallery($container, label, photos) {
        $container.empty();
        if (!photos || !photos.length) return;

        // Label — Frappe native style
        var $label = $('<div class="control-label" style="margin-bottom:8px;"></div>').text(label);
        $container.append($label);

        // Thumbnails row
        var $gallery = $('<div style="display:flex;flex-wrap:wrap;gap:8px;align-items:center;"></div>');
        photos.forEach(function(photo) {
            var safeUrl = frappe.utils.escape_html(photo.url || '');
            var safeTitle = frappe.utils.escape_html(photo.filename || 'Photo');

            var $thumb = $('<button type="button" style="display:block;padding:0;border:0;background:transparent;line-height:0;cursor:pointer;"></button>');
            var $img = $('<img />').attr('src', safeUrl).attr('title', safeTitle).css({
                width: '76px', height: '76px', objectFit: 'cover',
                border: '1px solid #d1d8dd', borderRadius: '6px', background: '#f8f9fa'
            });
            $thumb.append($img);
            $thumb.on('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                openFullscreen(photo.url, photo.filename);
                return false;
            });
            $gallery.append($thumb);
        });
        $container.append($gallery);
    }

    function openFullscreen(url, title) {
        // Use shared PhotoFullscreen if available (loaded from Task-Photo-System)
        if (window.PhotoFullscreen && window.PhotoFullscreen.open) {
            window.PhotoFullscreen.open(url, title);
            return;
        }
        // Fallback: simple fullscreen overlay
        var safeUrl = frappe.utils.escape_html(url || '');
        var safeTitle = frappe.utils.escape_html(title || 'Photo');
        var $overlay = $('<div style="position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,0.9);z-index:10000;display:flex;align-items:center;justify-content:center;flex-direction:column;"></div>');
        var $close = $('<button type="button" style="position:absolute;top:16px;right:16px;font-size:28px;color:#fff;background:transparent;border:none;cursor:pointer;z-index:10001;">&times;</button>');
        $close.on('click', function() { $overlay.remove(); });
        var $img = $('<img />').attr('src', safeUrl).attr('title', safeTitle).css({ maxWidth: '90%', maxHeight: '85%', objectFit: 'contain', borderRadius: '4px' });
        $overlay.append($close).append($img);
        $overlay.on('click', function(e) { if (e.target === $overlay[0]) $overlay.remove(); });
        $(document).on('keydown.dc_fullscreen', function(e) { if (e.key === 'Escape') { $overlay.remove(); $(document).off('keydown.dc_fullscreen'); } });
        $('body').append($overlay);
    }

    frappe.ui.form.on('Dispatch Case', {
        refresh: function(frm) {
            // Hide legacy Attach fields
            ['delivery_photo', 'return_dropoff_photo'].forEach(function(f) {
                if (frm.fields_dict[f]) frm.set_df_property(f, 'hidden', 1);
            });

            // Ensure gallery containers exist
            if (!frm._dc_pickup_gallery_el) {
                frm._dc_pickup_gallery_el = $('<div class="dc-pickup-photos" style="margin-bottom:16px;"></div>');
                frm._dc_dropoff_gallery_el = $('<div class="dc-dropoff-photos" style="margin-bottom:16px;"></div>');

                // Insert into the photo_section area
                var $section = $(frm.fields_dict.photo_section && frm.fields_dict.photo_section.wrapper);
                if ($section.length) {
                    $section.find('.section-body, .form-section-body, .frappe-control').first().before(frm._dc_pickup_gallery_el).before(frm._dc_dropoff_gallery_el);
                    // If section body not found, append to section wrapper
                    if (!frm._dc_pickup_gallery_el.parent().length) {
                        $section.append(frm._dc_pickup_gallery_el).append(frm._dc_dropoff_gallery_el);
                    }
                } else {
                    // Fallback: append after form layout
                    $(frm.layout.wrapper).append(frm._dc_pickup_gallery_el).append(frm._dc_dropoff_gallery_el);
                }
            }

            // Fetch and render Pack task photos (Warehouse Pickup Photos)
            var packTask = frm.doc.pack_task;
            fetchTaskImages(packTask, function(photos) {
                renderReadonlyGallery(frm._dc_pickup_gallery_el, 'Warehouse Pickup Photos', photos);
            });

            // Fetch and render Pickup Returns task photos (Warehouse Drop-off Photos)
            var returnTask = frm.doc.return_pickup_task;
            fetchTaskImages(returnTask, function(photos) {
                renderReadonlyGallery(frm._dc_dropoff_gallery_el, 'Warehouse Drop-off Photos', photos);
            });
        }
    });
})();
