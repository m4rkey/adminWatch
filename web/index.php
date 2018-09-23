<?php

$PRECISION = 0; // Set to 1 if using minutes

/* Do not edit below this line unless you know what youre doing */
require('includes/database.include.php');

function convertTime ($time) 
{
	if ($PRECISION == 0)
    	return sprintf("%02d:%02d:%02d", floor($time / 3600), ($time / 60) % 60, $time % 60);

    return sprintf("%d:%02d", floor($time / 60), (abs($time) % 60)); 
} 

$db = new Database();
$db->query('SELECT * FROM `adminwatch`');

$admins = array ();
$totalIdle = 0;
$totalPlayed = 0;
while ($db->nextRecord())
{
	if ($db->Record['last_played'] == '')
	{
		$date = 'Not Available';
	}
	else
	{
		$date = new DateTime('@'.$db->Record['last_played']);
		$date = $date->format('F j, Y, g:i a');
	}
	$admins[] = array (
		'steam' => $db->Record['steam'],
		'name' => $db->Record['name'],
		'total' => convertTime($db->Record['total']),
		'played' => convertTime($db->Record['played']),
		'last_played' => $date
	);

	$totalIdle += $db->Record['total'];
	$totalPlayed += $db->Record['played'];
}
?>

<!DOCTYPE html>
<html class="no-js" lang="en" xml:lang="en"><head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>adminWatch Statistics</title>
<link href="includes/style.css" rel="stylesheet">
<script src="includes/jquery.min.js" type="text/javascript"></script>
<script type="text/javascript">
	jQuery(document).ready(function($) {
		$('h3').click(function(e) {
			$(this).toggleClass('closed');
			$(this).next('section').toggle();
		});
	});
</script>
</head>
<body>
<div id="wrap">

	<h1>adminWatch Statistics</h1>

	<div id="content">
<div class="cf">
	<div class="summary-box">Total Idle: <?php echo convertTime($totalIdle); ?></div>
	<div class="summary-box">Total Played: <?php echo convertTime($totalPlayed); ?></div>
</div>
	<h3>Individual Stats:</h3>
	<section>
		<?php
		foreach ($admins as $admin) {
		?>
		<div class="task">
			<h4><?php echo $admin['name']; ?></h4>
			<p><em>Steam</em>: <?php echo $admin['steam']; ?></p>
			<p><em>Last Played</em>: <?php echo $admin['last_played']; ?></p>
			<p class="score">Idle: <?php echo $admin['total']; ?>, Played: <?php echo $admin['played']; ?></p>
		</div>
		<?php
		}
		?>
	</section>
	<h3 class="closed">Command Logs:</h3>
	<section style="display:none;">
		<?php
		$db = new Database();
		$db->query('SELECT * FROM `adminwatch_logs` ORDER BY `id` DESC LIMIT 25');
		while ($db->nextRecord()) {
			if ($db->Record['time'] != '')
			{
				$date = new DateTime('@'.$db->Record['time']);
				$date = $date->format('F j, Y, g:i a');
			}
			else
			{
				$date = 'No Data Available';
			}
			
		?>
		<div class="task">
			<h4><?php echo $db->Record['name']; ?></h4>
			<p><em>Server</em>: <?php echo $db->Record['hostname']; ?></p>
			<p><em>Steam</em>: <?php echo $db->Record['steam']; ?></p>
			<p><em>Command</em>: <?php echo $db->Record['command']; ?></p>
			<p class="score">Date: <?php echo $date; ?></p>
		</div>
		<?php
		}
		?>
	</section>
</div>

	<div id="footer">
		Created by Pat841
	</div>
</div>
</body></html>