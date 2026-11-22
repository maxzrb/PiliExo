@file:JvmName("MpvHdrLayoutFate")

package com.maxzrb.piliexo

fun main() {
    System.`in`.bufferedReader(Charsets.UTF_8).lineSequence().forEach { line ->
        val columns = line.split(' ')
        require(columns.size == 6)
        val mode = MpvResizeMode.fromWire(columns[1])
        val size = mode.surfaceSize(
            columns[2].toInt(),
            columns[3].toInt(),
            columns[4].toInt(),
            columns[5].toInt(),
        )
        val bounds = size?.let { "${it.first}x${it.second}" } ?: "pending"
        println("${columns[0]} ${mode.wireName} ${bounds} keepaspect=${mode.keepAspect}")
    }
}
