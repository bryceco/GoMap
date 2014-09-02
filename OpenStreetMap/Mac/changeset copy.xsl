<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

	<xsl:template match="/osmChange">
		<html xsl:version="1.0" xmlns="http://www.w3.org/1999/xhtml">
			<body style="font-family:Arial;font-size:10pt;background-color:#EEEEEE">
				<xsl:apply-templates select="delete"/>
				<xsl:apply-templates select="create"/>
				<xsl:apply-templates select="modify"/>
			</body>
		</html>
	</xsl:template>

	
	<xsl:template match="delete">
		<h2>Delete</h2>
		<xsl:apply-templates select="node"/>
		<xsl:apply-templates select="way"/>
	</xsl:template>

	<xsl:template match="create">
		<h2>Create</h2>
		<xsl:apply-templates select="node"/>
		<xsl:apply-templates select="way"/>
	</xsl:template>

	<xsl:template match="modify">
		<h2>Modify</h2>
		<xsl:apply-templates select="node"/>
		<xsl:apply-templates select="way"/>
	</xsl:template>


	<xsl:template match="node">
		<div style="padding:4px">
			<span style="font-weight:bold">Node <xsl:value-of select="@id"/></span>
			(<xsl:value-of select="@lat"/>,<xsl:value-of select="@lon"/>)
		</div>
		<xsl:apply-templates select="tag"/>
	</xsl:template>

	<xsl:template match="way">
		<div style="padding:4px">
			<span style="font-weight:bold">Way <xsl:value-of select="@id"/></span> (<xsl:value-of select="count(nd)"/> nodes)
		</div>
		<xsl:apply-templates select="tag"/>
	</xsl:template>


	<xsl:template match="tag">
		<div style="margin-left:20px;font-size:10pt">
			<xsl:value-of select="description"/>
			<span style="">
				<xsl:value-of select="@k"/> = <xsl:value-of select="@v"/>
			</span>
		</div>
	</xsl:template>

</xsl:stylesheet> 
