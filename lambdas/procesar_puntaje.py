import json
import os
import boto3

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    table_name = os.environ.get('TABLE_NAME', 'Puntajes')
    table = dynamodb.Table(table_name)
    
    records = event.get('Records', [])
    for record in records:
        body = json.loads(record['body'])
        juego = body['juego']
        jugador = body['jugador']
        nuevo_puntaje = int(body['puntaje'])
        
        response = table.get_item(Key={'juego': juego, 'jugador': jugador})
        existing_item = response.get('Item')
        
        if not existing_item or nuevo_puntaje > int(existing_item.get('puntaje', 0)):
            table.put_item(
                Item={
                    'juego': juego,
                    'jugador': jugador,
                    'puntaje': nuevo_puntaje
                }
            )
            
    return {'statusCode': 200, 'body': 'Procesado con éxito'}
