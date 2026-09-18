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
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import java.time.Duration
import java.time.Instant

object FlamesHealthConnect {
    const val PROVIDER_PACKAGE = "com.google.android.apps.healthdata"

    // On Android 14 a Health Connect call can suspend forever; every native
    // read must be bounded so the catch blocks return a structured error
    // instead of hanging the Dart caller. Timeouts must nest strictly:
    // native 4s < Dart wrapper 5s < Dart service 6s < registry 10s.
    private const val READ_TIMEOUT_MS = 4_000L

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
    ): Map<String, Any> {
        val start = Instant.ofEpochMilli(startTimeMs)
        val end = Instant.ofEpochMilli(endTimeMs)
        val payload: MutableMap<String, Any> = mutableMapOf(
            "metric" to metric,
            "start" to start.toString(),
            "end" to end.toString(),
        )
        if (permissionFor(metric) == null) {
            payload["error_code"] = "health_unsupported_metric"
            payload["error_message"] = "Unsupported metric: $metric"
            return payload
        }
        return try {
            val client = HealthConnectClient.getOrCreate(context)
            val filter = TimeRangeFilter.between(start, end)
            when (metric) {
                "steps" -> readSteps(client, filter, payload)
                "heart_rate" -> readHeartRate(client, filter, payload)
                "calories" -> readCalories(client, filter, payload)
                "sleep" -> readSleep(client, filter, payload)
                "spo2" -> readSpo2(client, filter, payload)
                "weight" -> readWeight(client, filter, payload)
            }
            payload
        } catch (e: TimeoutCancellationException) {
            errorPayload(metric, start, end, e)
        } catch (e: Throwable) {
            errorPayload(metric, start, end, e)
        }
    }

    private fun errorPayload(
        metric: String,
        start: Instant,
        end: Instant,
        e: Throwable,
    ): Map<String, Any> = mapOf(
        "metric" to metric,
        "start" to start.toString(),
        "end" to end.toString(),
        "error_code" to errorCode(e),
        "error_message" to errorMessage(e),
    )

    private fun errorCode(e: Throwable): String = when (e) {
        is TimeoutCancellationException -> "health_timeout"
        else -> "health_platform_error"
    }

    private fun errorMessage(e: Throwable): String =
        "${e.javaClass.simpleName}: ${e.message ?: "no message"}"

    private suspend fun attachRecords(
        payload: MutableMap<String, Any>,
        loader: suspend () -> List<Map<String, Any>>,
    ): List<Map<String, Any>>? = try {
        val records = loader()
        payload["records"] = records
        records
    } catch (e: Throwable) {
        payload["records"] = emptyList<Map<String, Any>>()
        payload["records_unavailable"] = true
        payload["records_error"] = errorMessage(e)
        null
    }

    private suspend fun readSteps(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val result = withTimeout(READ_TIMEOUT_MS) {
            client.aggregate(AggregateRequest(setOf(StepsRecord.COUNT_TOTAL), filter))
        }
        val total = result.get(StepsRecord.COUNT_TOTAL) ?: 0L
        payload["summary"] = mapOf<String, Any>("total" to total)
        attachRecords(payload) {
            val response = withTimeout(READ_TIMEOUT_MS) {
                client.readRecords(
                    ReadRecordsRequest(
                        recordType = StepsRecord::class,
                        timeRangeFilter = filter,
                        pageSize = 200,
                    )
                )
            }
            val records = mutableListOf<Map<String, Any>>()
            for (record in response.records) {
                records.add(
                    mapOf<String, Any>(
                        "start" to record.startTime.toString(),
                        "end" to record.endTime.toString(),
                        "count" to record.count,
                    )
                )
            }
            records
        }
    }

    private suspend fun readHeartRate(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val result = withTimeout(READ_TIMEOUT_MS) {
            client.aggregate(
                AggregateRequest(
                    setOf(
                        HeartRateRecord.BPM_MIN,
                        HeartRateRecord.BPM_MAX,
                        HeartRateRecord.BPM_AVG,
                        HeartRateRecord.MEASUREMENTS_COUNT,
                    ),
                    filter,
                )
            )
        }
        payload["summary"] = mapOf<String, Any>(
            "min" to (result.get(HeartRateRecord.BPM_MIN) ?: 0L),
            "max" to (result.get(HeartRateRecord.BPM_MAX) ?: 0L),
            "avg" to (result.get(HeartRateRecord.BPM_AVG) ?: 0L).toDouble(),
            "samples" to (result.get(HeartRateRecord.MEASUREMENTS_COUNT) ?: 0L),
        )
        attachRecords(payload) {
            val response = withTimeout(READ_TIMEOUT_MS) {
                client.readRecords(
                    ReadRecordsRequest(
                        recordType = HeartRateRecord::class,
                        timeRangeFilter = filter,
                        pageSize = 200,
                    )
                )
            }
            val records = mutableListOf<Map<String, Any>>()
            for (record in response.records) {
                for (sample in record.samples) {
                    records.add(
                        mapOf<String, Any>(
                            "time" to sample.time.toString(),
                            "bpm" to sample.beatsPerMinute,
                        )
                    )
                }
            }
            records
        }
    }

    private suspend fun readCalories(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val result = withTimeout(READ_TIMEOUT_MS) {
            client.aggregate(AggregateRequest(setOf(TotalCaloriesBurnedRecord.ENERGY_TOTAL), filter))
        }
        val totalKcal = result.get(TotalCaloriesBurnedRecord.ENERGY_TOTAL)?.inKilocalories ?: 0.0
        payload["summary"] = mapOf<String, Any>("total_kcal" to totalKcal)
        attachRecords(payload) {
            val response = withTimeout(READ_TIMEOUT_MS) {
                client.readRecords(
                    ReadRecordsRequest(
                        recordType = TotalCaloriesBurnedRecord::class,
                        timeRangeFilter = filter,
                        pageSize = 200,
                    )
                )
            }
            val records = mutableListOf<Map<String, Any>>()
            for (record in response.records) {
                records.add(
                    mapOf<String, Any>(
                        "start" to record.startTime.toString(),
                        "end" to record.endTime.toString(),
                        "kcal" to record.energy.inKilocalories,
                    )
                )
            }
            records
        }
    }

    private suspend fun readSleep(
        client: HealthConnectClient,
        filter: TimeRangeFilter,
        payload: MutableMap<String, Any>,
    ) {
        val result = withTimeout(READ_TIMEOUT_MS) {
            client.aggregate(AggregateRequest(setOf(SleepSessionRecord.SLEEP_DURATION_TOTAL), filter))
        }
        val totalMinutes = result.get(SleepSessionRecord.SLEEP_DURATION_TOTAL)?.toMinutes() ?: 0L
        val records = attachRecords(payload) {
            val response = withTimeout(READ_TIMEOUT_MS) {
                client.readRecords(
                    ReadRecordsRequest(
                        recordType = SleepSessionRecord::class,
                        timeRangeFilter = filter,
                        pageSize = 200,
                    )
                )
            }
            val list = mutableListOf<Map<String, Any>>()
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
                list.add(
                    mapOf<String, Any>(
                        "start" to record.startTime.toString(),
                        "end" to record.endTime.toString(),
                        "duration_minutes" to minutes,
                        "stages" to stages,
                    )
                )
            }
            list
        }
        payload["summary"] = mapOf<String, Any>(
            "sessions" to (records?.size?.toLong() ?: 0L),
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
                ReadRecordsRequest(
                    recordType = OxygenSaturationRecord::class,
                    timeRangeFilter = filter,
                    pageSize = 200,
                )
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
        val result = withTimeout(READ_TIMEOUT_MS) {
            client.aggregate(AggregateRequest(setOf(WeightRecord.WEIGHT_AVG), filter))
        }
        var latestKg = result.get(WeightRecord.WEIGHT_AVG)?.inKilograms ?: 0.0
        attachRecords(payload) {
            val response = withTimeout(READ_TIMEOUT_MS) {
                client.readRecords(
                    ReadRecordsRequest(
                        recordType = WeightRecord::class,
                        timeRangeFilter = filter,
                        pageSize = 200,
                    )
                )
            }
            val records = mutableListOf<Map<String, Any>>()
            var latestTime: Instant? = null
            for (record in response.records) {
                val kg = record.weight.inKilograms
                records.add(
                    mapOf<String, Any>(
                        "time" to record.time.toString(),
                        "kg" to kg,
                    )
                )
                val previous = latestTime
                if (previous == null || record.time.isAfter(previous)) {
                    latestTime = record.time
                    latestKg = kg
                }
            }
            records
        }
        payload["summary"] = mapOf<String, Any>("latest_kg" to latestKg)
    }
}
