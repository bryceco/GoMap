<?php
# Unpack an uploaded archive into brandIcons2/, preserving subdirectory structure.
$path = 'brandIcons2/archive.zip';
echo 'unpacking zip at ', $path, ': ';
$zip = new ZipArchive;
$res = $zip->open($path);
if ($res === TRUE) {
	$zip->extractTo('./brandIcons2/');
	$zip->close();
	unlink($path);
	echo 'extracted!';
} else {
	echo 'zip archive not found!';
}
?>
