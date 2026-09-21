"""Jobs batch nocturnos.

Cada job es un modulo ejecutable que reutiliza el codigo del servicio:

    python -m app.jobs.ranking_prendas_puente
    python -m app.jobs.ajuste_preferencias

Viven aqui y no en un servicio aparte porque comparten configuracion, acceso a
datos y telemetria con el servicio. En AWS corren con la MISMA imagen del
servicio y distinto comando, disparados por EventBridge Scheduler como ECS
Scheduled Tasks. Asi no hay una segunda imagen que mantener ni un contenedor
encendido toda la noche sin hacer nada.
"""
