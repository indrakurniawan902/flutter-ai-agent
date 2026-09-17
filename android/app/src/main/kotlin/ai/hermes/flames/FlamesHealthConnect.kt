package ai.hermes.flames

import android.content.Context
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.withTimeout
import java.time.Duration
import java.time.Instant

object FlamesHealthConnect {
    const val PROVIDER_PACKAGE = "com.google.android.apps.healthdata"

    // On Android 14 a Health Connect call can suspend forever; every native
    // read must be bounded so the existing catch blocks return a structured
    // null/empty result instead of hanging the Dart caller.
    private const val READ_TIMEOUT_MS = 8_000L

    val readPermissions: Set<String> = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(OxygenSaturationRecord::class),
        HealthPermission.getReadPermission(WeightRecord::class),
    )

    fun permissionFor(metric: String): String? = when (metric) {
        "steps" -> HealthPermission.getReadPermission(StepsRecord::class)
        "heart_rate" -> HealthPermission.getReadPermission(HeartRateRecord::class)
        "calories" -> HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class)
        "sleep" -> HealthPermission.getReadPermission(SleepSessionRecord::class)
        "spo2" -> HealthPermission.getReadPermission(OxygenSaturationRecord::class)
        "weight" -> HealthPermission.getReadPermission(WeightRecord::class)
        else -> null
    }

    fun availability(context: Context): Map<String, Any> {
        val status = try {
            when (HealthConnectClient.getSdkStatus(context, PROVIDER_PACKAGE)) {
                HealthConnectClient.SDK_AVAILABLE -> "available"
                HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "update_required"
                else -> "unavailable"
            }
        } catch (_: Throwable) {
            "unavailable"
        }
        val installed = try {
            context.packageManager.getPackageInfo(PROVIDER_PACKAGE, 0)
            true
        } catch (_: Throwable) {
            false
        }
        return mapOf(
            "status" to status,
            "sdk_int" to Build.VERSION.SDK_INT,
            "provider_installed" to installed,
        )
    }

    suspend fun grantedPermissions(context: Context): Set<String> = try {
        withTimeout(READ_TIMEOUT_MS) {
            HealthConnectClient.getOrCreate(context).permissionController.getGrantedPermissions()
        }
    } catch (_: Throwable) {
        emptySet()
    }

    suspend fun readMetric(
        context: Context,
        metric: String,
        startTimeMs: Long,
        endTimeMs: Long,
    ): Map<String, Any>? {
        if (permissionFor(metric) == null) return null
        val start = Instant.ofEpochMilli(startTimeMs)
        val end = Instant.ofEpochMilli(endTimeMs)
        return try {
            val client = HealthConnectClient.getOrCreate(context)
            val filter = TimeRangeFilter.between(start, end)
            val payload: MutableMap<String, Any> = mutableMapOf(
                "metric" to metric,
                "start" to start.toString(),
                "end" to end.toString(),
            )
            when (metric) {
                "steps" -> readSteps(client, filter, payload)
                "heart_rate" -> readHeartRate(client, filter, payload)
                "calories" -> readCalories(client, filter, payload)
                "sleep" -> readSleep(client, filter, payload)
                "spo2" -> readSpo2(client, filter, payload)
                "weight" -> readWeight(client, filter, payload)
            }
            payload
        } catch (_: Throwable) {
            null
        }
    }

    private suspend fun readSteps(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val response = withTimeout(READ_TIMEOUT_MS) {
            client.readRecords(
                ReadRecordsRequest(recordType = StepsRecord::class, timeRangeFilter = filter)
            )
        }
        val records = mutableListOf<Map<String, Any>>()
        var total = 0L
        for (record in response.records) {
            records.add(
                mapOf<String, Any>(
                    "start" to record.startTime.toString(),
                    "end" to record.endTime.toString(),
                    "count" to record.count,
                )
            )
            total += record.count
        }
        payload["records"] = records
        payload["summary"] = mapOf<String, Any>("total" to total)
    }

    private suspend fun readHeartRate(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val response = withTimeout(READ_TIMEOUT_MS) {
            client.readRecords(
                ReadRecordsRequest(recordType = HeartRateRecord::class, timeRangeFilter = filter)
            )
        }
        val records = mutableListOf<Map<String, Any>>()
        var min = Long.MAX_VALUE
        var max = Long.MIN_VALUE
        var sum = 0L
        var count = 0
        for (record in response.records) {
            for (sample in record.samples) {
                val bpm = sample.beatsPerMinute
                records.add(
                    mapOf<String, Any>(
                        "time" to sample.time.toString(),
                        "bpm" to bpm,
                    )
                )
                if (bpm < min) min = bpm
                if (bpm > max) max = bpm
                sum += bpm
                count++
            }
        }
        val avg = if (count > 0) sum.toDouble() / count else 0.0
        payload["records"] = records
        payload["summary"] = mapOf<String, Any>(
            "min" to (if (count > 0) min else 0L),
            "max" to (if (count > 0) max else 0L),
            "avg" to avg,
            "samples" to count,
        )
    }

    private suspend fun readCalories(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val response = withTimeout(READ_TIMEOUT_MS) {
            client.readRecords(
                ReadRecordsRequest(recordType = TotalCaloriesBurnedRecord::class, timeRangeFilter = filter)
            )
        }
        val records = mutableListOf<Map<String, Any>>()
        var total = 0.0
        for (record in response.records) {
            val kcal = record.energy.inKilocalories
            records.add(
                mapOf<String, Any>(
                    "start" to record.startTime.toString(),
                    "end" to record.endTime.toString(),
                    "kcal" to kcal,
                )
            )
            total += kcal
        }
        payload["records"] = records
        payload["summary"] = mapOf<String, Any>("total_kcal" to total)
    }

    private suspend fun readSleep(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val response = withTimeout(READ_TIMEOUT_MS) {
            client.readRecords(
                ReadRecordsRequest(recordType = SleepSessionRecord::class, timeRangeFilter = filter)
            )
        }
        val records = mutableListOf<Map<String, Any>>()
        var totalMinutes = 0L
        for (record in response.records) {
            val stages = mutableListOf<Map<String, Any>>()
            for (stage in record.stages) {
                stages.add(
                    mapOf<String, Any>(
                        "stage" to stage.stage.toString(),
                        "start" to stage.startTime.toString(),
                        "end" to stage.endTime.toString(),
                    )
                )
            }
            val minutes = Duration.between(record.startTime, record.endTime).toMinutes()
            records.add(
                mapOf<String, Any>(
                    "start" to record.startTime.toString(),
                    "end" to record.endTime.toString(),
                    "duration_minutes" to minutes,
                    "stages" to stages,
                )
            )
            totalMinutes += minutes
        }
        payload["records"] = records
        payload["summary"] = mapOf<String, Any>(
            "sessions" to response.records.size,
            "total_minutes" to totalMinutes,
        )
    }

    private suspend fun readSpo2(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val response = withTimeout(READ_TIMEOUT_MS) {
            client.readRecords(
                ReadRecordsRequest(recordType = OxygenSaturationRecord::class, timeRangeFilter = filter)
            )
        }
        val records = mutableListOf<Map<String, Any>>()
        var min = Double.MAX_VALUE
        var max = -Double.MAX_VALUE
        var sum = 0.0
        var count = 0
        for (record in response.records) {
            val value = record.percentage.value
            records.add(
                mapOf<String, Any>(
                    "time" to record.time.toString(),
                    "percent" to value,
                )
            )
            if (value < min) min = value
            if (value > max) max = value
            sum += value
            count++
        }
        val avg = if (count > 0) sum / count else 0.0
        payload["records"] = records
        payload["summary"] = mapOf<String, Any>(
            "min" to (if (count > 0) min else 0.0),
            "max" to (if (count > 0) max else 0.0),
            "avg" to avg,
        )
    }

    private suspend fun readWeight(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val response = withTimeout(READ_TIMEOUT_MS) {
            client.readRecords(
                ReadRecordsRequest(recordType = WeightRecord::class, timeRangeFilter = filter)
            )
        }
        val records = mutableListOf<Map<String, Any>>()
        var latestKg = 0.0
        var latestTime: Instant? = null
        for (record in response.records) {
            val kg = record.weight.inKilograms
            records.add(
                mapOf<String, Any>(
                    "time" to record.time.toString(),
                    "kg" to kg,
                )
            )
            if (latestTime == null || record.time.isAfter(latestTime)) {
                latestTime = record.time
                latestKg = kg
            }
        }
        payload["records"] = records
        payload["summary"] = mapOf<String, Any>("latest_kg" to latestKg)
    }
}
