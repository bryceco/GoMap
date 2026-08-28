<?php
# Return a space-separated list of all logos in brandIcons2/ as featureIDs
# (path relative to brandIcons2/, without the .png extension).
# Example entry: brands/amenity/fast_food/mcdonalds-c9aa1b
function list_files(string $dir, int $base_len): array {
	$result = [];
	foreach (scandir($dir) as $item) {
		if ($item === '.' || $item === '..') continue;
		$path = $dir . '/' . $item;
		if (is_dir($path)) {
			$result = array_merge($result, list_files($path, $base_len));
		} else {
			// Strip the base-dir prefix and the .png extension to get the featureID
			$result[] = preg_replace('/\.png$/', '', substr($path, $base_len));
		}
	}
	return $result;
}

$base = 'brandIcons2/';
echo is_dir($base) ? implode(' ', list_files($base, strlen($base))) : '';
?>
