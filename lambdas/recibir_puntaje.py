import json
import os
import boto3

sqs = boto3.client('sqs')

def lambda_handler(event, context):
    queue_url = os.environ.get('QUEUE_URL')
    
    try:
        body = event.get('body')
        if isinstance(body, str):
            data = json.loads(body)
        elif isinstance(body, dict):
            data = body
        else:
            data = event
            
        jugador = data.get('jugador')
        juego = data.get('juego')
        puntaje = data.get('puntaje')
        
        if not jugador or not juego or not isinstance(puntaje, int):
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'Datos inválidos. Requiere jugador (str), juego (str) y puntaje (int)'})
            }
            
        payload = {
            'jugador': str(jugador),
            'juego': str(juego),
            'puntaje': int(puntaje)
        }
        
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(payload)
        )
        
        return {
            'statusCode': 202,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'message': 'Puntaje encolado correctamente'})
        }
        
    except Exception as e:
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': str(e)})
        }
